import Foundation
import TaisaContracts
import TaisaStorage

public protocol VoiceTurnCheckpointing: Sendable {
    func checkpoint(_ record: VoiceTurnRecord) async throws
}

public protocol VoiceTranscriptionRunning: Sendable {
    func stream(for turn: VoiceTurnRecord) async throws -> AsyncThrowingStream<TranscriptionStreamEvent, Error>
}

public protocol VoiceCoachingRunning: Sendable {
    func stream(for turn: VoiceTurnRecord) async throws -> AsyncThrowingStream<CoachingStreamEvent, Error>
}

public enum CoachingReconciliationResult: Sendable, Equatable {
    case safeToRetry
    case ambiguous
    case completed(receipt: String, assistantMessageID: String)
    case failed(code: String, retryable: Bool)
}

public protocol CoachingReconciliationLookingUp: Sendable {
    func reconcile(requestID: UUID) async throws -> CoachingReconciliationResult
}

public struct VoiceSessionSnapshot: Sendable, Equatable, CustomStringConvertible, CustomReflectable {
    public let durable: VoiceTurnRecord
    public let partialTranscript: String
    public let partialCoaching: String

    public init(
        durable: VoiceTurnRecord,
        partialTranscript: String,
        partialCoaching: String
    ) {
        self.durable = durable
        self.partialTranscript = partialTranscript
        self.partialCoaching = partialCoaching
    }

    public var requiresResumeConfirmation: Bool {
        durable.state == .resumeRequiresConfirmation
    }

    public var description: String {
        "VoiceSessionSnapshot(state: \(durable.state.rawValue), stage: \(durable.stage.rawValue), content: redacted)"
    }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "state": durable.state.rawValue,
                "stage": durable.stage.rawValue,
                "content": "redacted",
            ],
            displayStyle: .struct
        )
    }
}

/// Serializes commands around the durable reducer. The checkpoint effect is
/// committed before any subsequent network or UI-policy effect is executed.
public actor VoiceSessionCoordinator {
    private let reducer: VoiceSessionReducer
    private let checkpoints: any VoiceTurnCheckpointing
    private let transcription: any VoiceTranscriptionRunning
    private let coaching: any VoiceCoachingRunning
    private let connectivity: any ConnectivityMonitoring
    private let reconciliation: any CoachingReconciliationLookingUp
    private let makeMessageID: @Sendable () -> UUID

    private var durable: VoiceTurnRecord
    private var partialTranscript = ""
    private var partialCoaching = ""
    private var activeStage: VoiceTurnStage?

    public init(
        initial: VoiceTurnRecord,
        checkpoints: any VoiceTurnCheckpointing,
        transcription: any VoiceTranscriptionRunning,
        coaching: any VoiceCoachingRunning,
        connectivity: any ConnectivityMonitoring,
        reconciliation: any CoachingReconciliationLookingUp,
        reducer: VoiceSessionReducer = .init(),
        makeMessageID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        durable = initial
        self.checkpoints = checkpoints
        self.transcription = transcription
        self.coaching = coaching
        self.connectivity = connectivity
        self.reconciliation = reconciliation
        self.reducer = reducer
        self.makeMessageID = makeMessageID
    }

    public func snapshot() -> VoiceSessionSnapshot {
        VoiceSessionSnapshot(
            durable: durable,
            partialTranscript: partialTranscript,
            partialCoaching: partialCoaching
        )
    }

    public func send(_ command: VoiceSessionCommand) async throws {
        try await apply(reducer.reduce(state: durable, command: command))
    }

    public func connectivityChanged(isAvailable: Bool) async throws {
        guard isAvailable else { return }
        try await recoverIfAuthorized()
    }

    public func recoverIfAuthorized() async throws {
        guard activeStage == nil, await connectivity.isAvailable() else { return }

        switch VoiceSessionRecovery.action(for: durable) {
        case .none, .requireConfirmation, .cleanupOnly:
            return
        case .retryTranscription:
            if durable.state == .recoverableFailure {
                try await send(.retry)
            } else {
                try await runTranscription()
            }
        case .retryCoaching:
            try await runCoaching()
        case .reconcileCoaching:
            try await reconcileCoaching()
        }
    }

    private func apply(_ transition: VoiceSessionTransition) async throws {
        for effect in transition.effects {
            switch effect {
            case .checkpoint(let record):
                try await checkpoints.checkpoint(record)
                durable = record
            case .startTranscription:
                guard await connectivity.isAvailable() else { continue }
                try await runTranscription()
            case .startCoaching:
                guard await connectivity.isAvailable() else { continue }
                try await runCoaching()
            case .requestTranscriptConfirmation, .requestResumeConfirmation,
                 .startRecording, .pauseRecording, .resumeRecording,
                 .cancelWork, .deleteAudio, .conversationReady:
                break
            }
        }
    }

    private func runTranscription() async throws {
        guard activeStage == nil else { return }
        activeStage = .transcription
        defer { activeStage = nil }

        if durable.state == .queued ||
            (durable.state == .recoverableFailure && durable.stage == .transcription) {
            try await send(.transcriptionBegan)
        }
        guard durable.state == .transcribing else { return }

        partialTranscript = ""
        do {
            let events = try await transcription.stream(for: durable)
            for try await event in events {
                switch event {
                case .delta(_, _, let delta):
                    partialTranscript += delta
                case .completed(let requestID, _, let text, _, let quality, _):
                    partialTranscript = ""
                    let receipt = requestID.uuidString.lowercased()
                    switch quality {
                    case .clear:
                        try await send(.transcriptCompleted(.clear(
                            text: text, receipt: receipt,
                            userMessageID: makeMessageID().uuidString
                        )))
                    case .uncertain:
                        try await send(.transcriptCompleted(.uncertain(text: text, receipt: receipt)))
                    }
                case .noSpeech(let requestID, _):
                    partialTranscript = ""
                    try await send(.transcriptCompleted(.noSpeech(
                        receipt: requestID.uuidString.lowercased()
                    )))
                case .failed:
                    partialTranscript = ""
                    try await send(.fail(
                        code: "TRANSCRIPTION_FAILED", retryable: true, ambiguous: false
                    ))
                }
            }
        } catch {
            partialTranscript = ""
            if durable.state == .transcribing {
                try await send(.fail(
                    code: "TRANSCRIPTION_TRANSPORT_FAILED", retryable: true, ambiguous: false
                ))
            }
            throw error
        }
    }

    private func runCoaching() async throws {
        guard activeStage == nil || activeStage == .transcription else { return }
        let previousStage = activeStage
        activeStage = .coaching
        defer { activeStage = previousStage }

        if durable.state == .transcriptClear ||
            (durable.state == .recoverableFailure && durable.stage == .coaching) {
            try await send(.coachingBegan)
        }
        guard durable.state == .coaching else { return }

        partialCoaching = ""
        do {
            let events = try await coaching.stream(for: durable)
            for try await event in events {
                switch event {
                case .delta(_, _, let delta):
                    partialCoaching += delta
                case .completed(_, _, _, let receipt):
                    partialCoaching = ""
                    try await send(.coachingCompleted(
                        receipt: receipt, assistantMessageID: makeMessageID().uuidString
                    ))
                case .failed(_, _, let code, let retryable):
                    partialCoaching = ""
                    try await send(.fail(
                        code: code.rawValue, retryable: retryable, ambiguous: false
                    ))
                }
            }
        } catch {
            partialCoaching = ""
            if durable.state == .coaching {
                try await send(.fail(
                    code: "COACHING_TRANSPORT_FAILED", retryable: true, ambiguous: true
                ))
            }
            throw error
        }
    }

    private func reconcileCoaching() async throws {
        guard let requestID = UUID(uuidString: durable.coachingRequestID) else {
            try await send(.fail(
                code: "INVALID_COACHING_REQUEST_ID", retryable: false, ambiguous: false
            ))
            return
        }

        switch try await reconciliation.reconcile(requestID: requestID) {
        case .safeToRetry:
            if durable.state == .recoverableFailure {
                try await send(.retry)
            } else {
                try await runCoaching()
            }
        case .ambiguous:
            try await send(.fail(
                code: "AMBIGUOUS_PAID_WORK", retryable: false, ambiguous: true
            ))
        case .completed(let receipt, let assistantMessageID):
            guard durable.state == .coaching else {
                try await send(.fail(
                    code: "AMBIGUOUS_PAID_WORK", retryable: false, ambiguous: true
                ))
                return
            }
            try await send(.coachingCompleted(
                receipt: receipt, assistantMessageID: assistantMessageID
            ))
        case .failed(let code, let retryable):
            try await send(.fail(code: code, retryable: retryable, ambiguous: false))
        }
    }
}
