import Foundation
import TaisaAudio
import TaisaContracts
import TaisaNetworking
import TaisaStorage

public protocol VoiceTurnCheckpointing: Sendable {
    func checkpoint(
        _ record: VoiceTurnRecord,
        messages: [MessageRecord],
        cleanup: VoiceTurnCleanup?
    ) async throws
}

public protocol VoiceTranscriptionRunning: Sendable {
    func stream(for turn: VoiceTurnRecord) async throws -> AsyncThrowingStream<TranscriptionStreamEvent, Error>
}

public enum TranscriptionReconciliationResult: Sendable, Equatable {
    case safeToRetry
    case ambiguous
    case completed(TranscriptionStreamEvent)
}

public protocol TranscriptionReconciliationLookingUp: Sendable {
    func reconcile(requestID: UUID) async throws -> TranscriptionReconciliationResult
    func authorizeRetry(requestID: UUID) async throws
}

public struct FailClosedTranscriptionReconciliation: TranscriptionReconciliationLookingUp {
    public init() {}
    public func reconcile(requestID: UUID) async throws -> TranscriptionReconciliationResult {
        .ambiguous
    }
    public func authorizeRetry(requestID: UUID) async throws {
        throw StreamTransportError.reconciliationRequired
    }
}

public protocol VoiceCoachingRunning: Sendable {
    func stream(for turn: VoiceTurnRecord) async throws -> AsyncThrowingStream<CoachingStreamEvent, Error>
}

public protocol VoiceCaptureControlling: Sendable {
    func events() async -> AsyncStream<AudioCaptureEvent>
    func prepare(turnID: UUID) async throws -> String
    func start(turnID: UUID) async throws
    func pause(turnID: UUID) async throws
    func resume(turnID: UUID) async throws
    func finalize(turnID: UUID) async throws -> FinalizedVoiceAudio
    func cancel(turnID: UUID) async throws
    func discard(turnID: UUID) async throws
    func release(turnID: UUID) async throws
}

public protocol VoiceAudioDeleting: Sendable {
    func delete(fileID: String) async throws
}

public enum CoachingReconciliationResult: Sendable, Equatable {
    case safeToRetry
    case ambiguous
    case completed(response: CoachingResponse, receipt: String)
    case failed(code: String, retryable: Bool)
}

public protocol CoachingReconciliationLookingUp: Sendable {
    func reconcile(requestID: UUID) async throws -> CoachingReconciliationResult
    func authorizeRetry(requestID: UUID) async throws
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
    private let transcriptionReconciliation: any TranscriptionReconciliationLookingUp
    private let coaching: any VoiceCoachingRunning
    private let connectivity: any ConnectivityMonitoring
    private let reconciliation: any CoachingReconciliationLookingUp
    private let capture: any VoiceCaptureControlling
    private let audio: any VoiceAudioDeleting
    private let retryScheduler: VoiceRetryScheduler
    private let retrySleeper: any VoiceRetrySleeping
    private let makeMessageID: @Sendable () -> UUID
    private let nowMS: @Sendable () -> Int64

    private var durable: VoiceTurnRecord
    private var partialTranscript = ""
    private var partialCoaching = ""
    private var pendingAssistantReply: String?
    private var activeStage: VoiceTurnStage?
    private var activeTask: Task<Void, Never>?
    private var captureEventsTask: Task<Void, Never>?
    private var operationGeneration = 0

    public init(
        initial: VoiceTurnRecord,
        checkpoints: any VoiceTurnCheckpointing,
        transcription: any VoiceTranscriptionRunning,
        transcriptionReconciliation: any TranscriptionReconciliationLookingUp = FailClosedTranscriptionReconciliation(),
        coaching: any VoiceCoachingRunning,
        connectivity: any ConnectivityMonitoring,
        reconciliation: any CoachingReconciliationLookingUp,
        capture: any VoiceCaptureControlling,
        audio: any VoiceAudioDeleting,
        reducer: VoiceSessionReducer = .init(),
        retryScheduler: VoiceRetryScheduler = .init(),
        retrySleeper: any VoiceRetrySleeping = SystemVoiceRetrySleeper(),
        makeMessageID: @escaping @Sendable () -> UUID = UUID.init,
        nowMS: @escaping @Sendable () -> Int64 = {
            Int64(Date().timeIntervalSince1970 * 1_000)
        }
    ) {
        durable = initial
        self.checkpoints = checkpoints
        self.transcription = transcription
        self.transcriptionReconciliation = transcriptionReconciliation
        self.coaching = coaching
        self.connectivity = connectivity
        self.reconciliation = reconciliation
        self.capture = capture
        self.audio = audio
        self.reducer = reducer
        self.retryScheduler = retryScheduler
        self.retrySleeper = retrySleeper
        self.makeMessageID = makeMessageID
        self.nowMS = nowMS
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

    public func sendRecordedAudio() async throws {
        let finalized = try await capture.finalize(turnID: currentTurnID())
        try await send(.send(finalized))
    }

    public func connectivityChanged(isAvailable: Bool) async throws {
        guard isAvailable else { return }
        try await recoverIfAuthorized()
    }

    public func recoverIfAuthorized() async throws {
        guard activeStage == nil else { return }
        if durable.stage == .capture, durable.state == .cancelled {
            try await send(.discard)
            return
        }
        if durable.stage == .capture,
           (durable.state == .recording || durable.state == .paused) {
            try await send(.captureFailed(code: "CAPTURE_INTERRUPTED"))
            return
        }
        guard await connectivity.isAvailable() else { return }

        switch VoiceSessionRecovery.action(for: durable) {
        case .none, .requireConfirmation:
            return
        case .cleanupOnly:
            if let fileID = durable.audioFileID, durable.cleanupState == .pending {
                try await deleteAudio(fileID)
            }
        case .retryTranscription:
            if durable.state == .recoverableFailure {
                scheduleDurableRetry(stage: .transcription)
            } else {
                launchTranscription()
            }
        case .reconcileTranscription:
            try await reconcileTranscription()
        case .retryCoaching:
            if durable.state == .recoverableFailure {
                scheduleDurableRetry(stage: .coaching)
            } else {
                launchCoaching()
            }
        case .reconcileCoaching:
            try await reconcileCoaching()
        }
    }

    public func waitForIdle() async {
        while activeStage != nil {
            if let task = activeTask {
                await task.value
            } else {
                await Task.yield()
            }
        }
    }

    private func apply(_ transition: VoiceSessionTransition) async throws {
        let prior = durable
        for effect in transition.effects {
            switch effect {
            case .checkpoint(let record):
                try await persist(record)
            case .startTranscription:
                guard await connectivity.isAvailable() else { continue }
                launchTranscription()
            case .startCoaching:
                guard await connectivity.isAvailable() else { continue }
                launchCoaching()
            case .startRecording:
                let turnID = try currentTurnID()
                let fileID = try await capture.prepare(turnID: turnID)
                do {
                    try await send(.captureStarted(fileID: fileID))
                } catch {
                    try? await capture.discard(turnID: turnID)
                    try? await capture.release(turnID: turnID)
                    try? await send(.captureFailed(code: "CAPTURE_CHECKPOINT_FAILED"))
                    throw error
                }
                do {
                    try await capture.start(turnID: turnID)
                } catch {
                    try? await send(.captureFailed(code: "CAPTURE_START_FAILED"))
                    throw error
                }
                observeCaptureEvents()
            case .pauseRecording:
                try await capture.pause(turnID: currentTurnID())
            case .resumeRecording:
                try await capture.resume(turnID: currentTurnID())
            case .authorizeCoachingRetry:
                guard let requestID = UUID(uuidString: durable.coachingRequestID) else {
                    throw VoiceSessionReducerError.invalidCommand
                }
                try await reconciliation.authorizeRetry(requestID: requestID)
                launchCoaching()
            case .authorizeTranscriptionRetry:
                guard let requestID = UUID(uuidString: durable.transcriptionRequestID) else {
                    throw VoiceSessionReducerError.invalidCommand
                }
                try await transcriptionReconciliation.authorizeRetry(requestID: requestID)
                launchTranscription()
            case .cancelWork:
                try await cancelWork(
                    prior: prior,
                    discardCapture: transition.next.state == .discarded
                )
            case .deleteAudio(let fileID):
                try await deleteAudio(fileID)
            case .completeCleanup:
                try await send(.cleanupCompleted)
            case .conversationReady:
                try await capture.release(turnID: currentTurnID())
            case .requestTranscriptConfirmation, .requestResumeConfirmation:
                break
            }
        }
    }

    private func persist(_ candidate: VoiceTurnRecord) async throws {
        let timestamp = max(
            nowMS(), durable.updatedAtMS == Int64.max ? Int64.max : durable.updatedAtMS + 1
        )
        let record = timestamped(candidate, at: timestamp)
        var messages: [MessageRecord] = []
        if record.userMessageID != durable.userMessageID,
           let id = record.userMessageID, let body = record.acceptedTranscript {
            messages.append(.init(
                id: id, conversationID: record.conversationID,
                role: "user", body: body, createdAtMS: timestamp
            ))
        }
        if record.assistantMessageID != durable.assistantMessageID,
           let id = record.assistantMessageID, let body = pendingAssistantReply {
            messages.append(.init(
                id: id, conversationID: record.conversationID,
                role: "assistant", body: body, createdAtMS: timestamp
            ))
        }
        let cleanup: VoiceTurnCleanup?
        if record.cleanupState == .completed, let fileID = durable.audioFileID {
            cleanup = .init(audioFileID: fileID, completedAtMS: timestamp)
        } else if record.cleanupState == .pending,
                  (record.state.isTerminal || record.state == .discarded),
                  let fileID = record.audioFileID {
            cleanup = .init(audioFileID: fileID, completedAtMS: nil)
        } else {
            cleanup = nil
        }
        try await checkpoints.checkpoint(record, messages: messages, cleanup: cleanup)
        durable = record
        if messages.contains(where: { $0.role == "assistant" }) { pendingAssistantReply = nil }
    }

    private func launchTranscription() {
        guard activeStage == nil || (activeStage == .transcription && activeTask == nil) else { return }
        operationGeneration += 1
        let generation = operationGeneration
        activeStage = .transcription
        activeTask = Task { [weak self] in
            await self?.consumeTranscription(generation: generation)
        }
    }

    private func consumeTranscription(generation: Int) async {
        do {
            if durable.state == .queued ||
                (durable.state == .recoverableFailure && durable.stage == .transcription) {
                try await send(.transcriptionBegan)
            }
            guard durable.state == .transcribing, isCurrent(generation) else {
                finishStage(generation)
                return
            }
            partialTranscript = ""
            for try await event in try await transcription.stream(for: durable) {
                try Task.checkCancellation()
                guard isCurrent(generation) else { return }
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
                    finishStage(generation)
                    return
                case .noSpeech(let requestID, _):
                    partialTranscript = ""
                    try await send(.transcriptCompleted(.noSpeech(
                        receipt: requestID.uuidString.lowercased()
                    )))
                    finishStage(generation)
                    return
                case .failed:
                    partialTranscript = ""
                    try await scheduleRetryOrFail(
                        code: "TRANSCRIPTION_FAILED", generation: generation
                    )
                    return
                }
            }
        } catch let error as StreamTransportError where error == .reconciliationRequired {
            partialTranscript = ""
            if isCurrent(generation), !Task.isCancelled, durable.state == .transcribing {
                try? await send(.fail(
                    code: "AMBIGUOUS_PAID_WORK", retryable: false, ambiguous: true
                ))
            }
            finishStage(generation)
        } catch {
            partialTranscript = ""
            if isCurrent(generation), !Task.isCancelled, durable.state == .transcribing {
                try? await scheduleRetryOrFail(
                    code: "TRANSCRIPTION_TRANSPORT_FAILED", generation: generation
                )
                return
            }
        }
        finishStage(generation)
    }

    private func launchCoaching() {
        guard activeStage != .coaching || activeTask == nil else { return }
        operationGeneration += 1
        let generation = operationGeneration
        activeStage = .coaching
        activeTask = Task { [weak self] in
            await self?.consumeCoaching(generation: generation)
        }
    }

    private func consumeCoaching(generation: Int) async {
        do {
            if durable.state == .transcriptClear ||
                (durable.state == .recoverableFailure && durable.stage == .coaching) {
                try await send(.coachingBegan)
            }
            guard durable.state == .coaching, isCurrent(generation) else {
                finishStage(generation)
                return
            }
            partialCoaching = ""
            for try await event in try await coaching.stream(for: durable) {
                try Task.checkCancellation()
                guard isCurrent(generation) else { return }
                switch event {
                case .delta(_, _, let delta):
                    partialCoaching += delta
                case .completed(_, _, let response, let receipt):
                    partialCoaching = ""
                    pendingAssistantReply = response.reply
                    try await send(.coachingCompleted(
                        receipt: receipt, assistantMessageID: makeMessageID().uuidString
                    ))
                    finishStage(generation)
                    return
                case .failed(_, _, let code, let retryable):
                    partialCoaching = ""
                    if retryable {
                        try await scheduleRetryOrFail(code: code.rawValue, generation: generation)
                    } else {
                        try await send(.fail(
                            code: code.rawValue, retryable: false, ambiguous: false
                        ))
                        finishStage(generation)
                    }
                    return
                }
            }
        } catch {
            partialCoaching = ""
            if isCurrent(generation), !Task.isCancelled, durable.state == .coaching {
                try? await send(.fail(
                    code: "COACHING_TRANSPORT_FAILED", retryable: true, ambiguous: true
                ))
            }
        }
        finishStage(generation)
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
                launchCoaching()
            }
        case .ambiguous:
            try await send(.fail(
                code: "AMBIGUOUS_PAID_WORK", retryable: false, ambiguous: true
            ))
        case .completed(let response, let receipt):
            guard durable.state == .coaching else {
                try await send(.fail(
                    code: "AMBIGUOUS_PAID_WORK", retryable: false, ambiguous: true
                ))
                return
            }
            pendingAssistantReply = response.reply
            try await send(.coachingCompleted(
                receipt: receipt, assistantMessageID: makeMessageID().uuidString
            ))
        case .failed(let code, let retryable):
            try await send(.fail(code: code, retryable: retryable, ambiguous: false))
        }
    }

    private func reconcileTranscription() async throws {
        guard let requestID = UUID(uuidString: durable.transcriptionRequestID) else {
            try await send(.fail(
                code: "INVALID_TRANSCRIPTION_REQUEST_ID", retryable: false, ambiguous: false
            ))
            return
        }
        switch try await transcriptionReconciliation.reconcile(requestID: requestID) {
        case .safeToRetry:
            launchTranscription()
        case .ambiguous:
            try await send(.fail(
                code: "AMBIGUOUS_PAID_WORK", retryable: false, ambiguous: true
            ))
        case .completed(let event):
            switch event {
            case .completed(let eventRequestID, _, let text, _, let quality, _):
                guard eventRequestID == requestID else {
                    throw StreamTransportError.protocolViolation(.requestMismatch)
                }
                switch quality {
                case .clear:
                    try await send(.transcriptCompleted(.clear(
                        text: text, receipt: requestID.uuidString.lowercased(),
                        userMessageID: makeMessageID().uuidString
                    )))
                case .uncertain:
                    try await send(.transcriptCompleted(.uncertain(
                        text: text, receipt: requestID.uuidString.lowercased()
                    )))
                }
            case .noSpeech(let eventRequestID, _):
                guard eventRequestID == requestID else {
                    throw StreamTransportError.protocolViolation(.requestMismatch)
                }
                try await send(.transcriptCompleted(.noSpeech(
                    receipt: requestID.uuidString.lowercased()
                )))
            case .failed:
                try await send(.fail(
                    code: "TRANSCRIPTION_FAILED", retryable: false, ambiguous: false
                ))
            case .delta:
                throw StreamTransportError.invalidResponse
            }
        }
    }

    private func cancelWork(
        prior: VoiceTurnRecord,
        discardCapture: Bool
    ) async throws {
        operationGeneration += 1
        activeTask?.cancel()
        activeTask = nil
        activeStage = nil
        partialTranscript = ""
        partialCoaching = ""
        captureEventsTask?.cancel()
        captureEventsTask = nil
        if prior.stage == .capture {
            guard let turnID = UUID(uuidString: prior.id) else {
                throw VoiceSessionReducerError.invalidCommand
            }
            if discardCapture {
                try await capture.discard(turnID: turnID)
                try await send(.cleanupCompleted)
            } else {
                try await capture.cancel(turnID: turnID)
            }
        }
    }

    private func observeCaptureEvents() {
        captureEventsTask?.cancel()
        captureEventsTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.capture.events() {
                guard !Task.isCancelled else { return }
                await self.captureEventReceived(event)
            }
        }
    }

    private func captureEventReceived(_ event: AudioCaptureEvent) async {
        let eventTurnID: UUID
        switch event {
        case .started(let turnID, _), .paused(let turnID, _), .resumed(let turnID),
             .blocked(let turnID, _), .finalized(let turnID, _),
             .finalizedAudioPreserved(let turnID, _),
             .cancelledAudioPreserved(let turnID, _), .discarded(let turnID, _):
            eventTurnID = turnID
        }
        guard eventTurnID.uuidString.lowercased() == durable.id else { return }
        guard durable.state == .recording else { return }
        switch event {
        case .blocked(_, .mediaServicesReset):
            try? await capture.discard(turnID: eventTurnID)
            try? await send(.captureFailed(code: "MEDIA_SERVICES_RESET"))
        case .paused, .blocked:
            try? await send(.capturePaused)
        default:
            break
        }
    }

    private func timestamped(_ source: VoiceTurnRecord, at updatedAtMS: Int64) -> VoiceTurnRecord {
        VoiceTurnRecord(
            id: source.id, conversationID: source.conversationID,
            transcriptionRequestID: source.transcriptionRequestID,
            transcriptionIdempotencyKey: source.transcriptionIdempotencyKey,
            coachingRequestID: source.coachingRequestID,
            coachingIdempotencyKey: source.coachingIdempotencyKey,
            state: source.state, stage: source.stage,
            audioFileID: source.audioFileID, audioSHA256: source.audioSHA256,
            audioDurationMS: source.audioDurationMS,
            acceptedTranscript: source.acceptedTranscript,
            uncertainTranscript: source.uncertainTranscript,
            retryCount: source.retryCount, nextRetryAtMS: source.nextRetryAtMS,
            failureCode: source.failureCode,
            transcriptionReceipt: source.transcriptionReceipt,
            coachingReceipt: source.coachingReceipt,
            userMessageID: source.userMessageID,
            assistantMessageID: source.assistantMessageID,
            cleanupState: source.cleanupState,
            createdAtMS: source.createdAtMS, updatedAtMS: updatedAtMS
        )
    }

    private func scheduleRetryOrFail(code: String, generation: Int) async throws {
        guard let delay = retryScheduler.delay(forAttempt: durable.retryCount) else {
            try await send(.fail(code: code, retryable: false, ambiguous: false))
            finishStage(generation)
            return
        }
        let delayMS = Int64((delay * 1_000).rounded(.up))
        let retryAt = nowMS() > Int64.max - delayMS ? Int64.max : nowMS() + delayMS
        try await send(.scheduleRetry(code: code, nextRetryAtMS: retryAt))
        try await retrySleeper.sleep(for: delay)
        guard isCurrent(generation), !Task.isCancelled else { return }
        guard await connectivity.isAvailable() else {
            finishStage(generation)
            return
        }
        activeTask = nil
        try await send(.retry)
    }

    private func scheduleDurableRetry(stage: VoiceTurnStage) {
        guard activeStage == nil else { return }
        operationGeneration += 1
        let generation = operationGeneration
        activeStage = stage
        let retryAt = durable.nextRetryAtMS ?? nowMS()
        let delay = TimeInterval(max(0, retryAt - nowMS())) / 1_000
        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.retrySleeper.sleep(for: delay)
                guard await self.isCurrent(generation), !Task.isCancelled else { return }
                guard await self.connectivity.isAvailable() else {
                    await self.finishStage(generation)
                    return
                }
                await self.prepareRetry(generation: generation)
                try await self.send(.retry)
            } catch {
                await self.finishStage(generation)
            }
        }
    }

    private func prepareRetry(generation: Int) {
        guard isCurrent(generation) else { return }
        activeTask = nil
    }

    private func deleteAudio(_ fileID: String) async throws {
        try await audio.delete(fileID: fileID)
        if durable.state.isTerminal, durable.cleanupState == .pending {
            try await send(.cleanupCompleted)
        }
    }

    private func currentTurnID() throws -> UUID {
        guard let id = UUID(uuidString: durable.id) else {
            throw VoiceSessionReducerError.invalidCommand
        }
        return id
    }

    private func isCurrent(_ generation: Int) -> Bool {
        operationGeneration == generation
    }

    private func finishStage(_ generation: Int) {
        guard isCurrent(generation) else { return }
        activeTask = nil
        activeStage = nil
    }
}
