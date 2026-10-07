import Foundation
import Testing
import TaisaContracts
import TaisaStorage
@testable import TaisaVoice

@Suite("Voice session coordinator")
struct VoiceSessionCoordinatorTests {
    @Test("offline Send checkpoints once and resumes one upload when network returns")
    func offlineSendQueuesThenAutoResumesOnceWhenNetworkReturns() async throws {
        let store = CheckpointSpy()
        let connectivity = ConnectivitySpy(available: false)
        let transcription = TranscriptionSpy(events: [.noSpeech(requestId: IDs.transcription, sequence: 0)])
        let coaching = CoachingSpy()
        let coordinator = VoiceSessionCoordinator(
            initial: turn(state: .recording, stage: .capture), checkpoints: store,
            transcription: transcription, coaching: coaching,
            connectivity: connectivity, reconciliation: ReconciliationSpy(.safeToRetry),
            capture: NoopCapture(), audio: NoopAudio()
        )

        try await coordinator.send(.send(.init(fileID: "audio-1", sha256: "abc", durationMS: 1000)))
        #expect(await transcription.calls == 0)
        #expect(await coordinator.snapshot().durable.state == .queued)

        await connectivity.setAvailable(true)
        try await coordinator.connectivityChanged(isAvailable: true)
        await coordinator.waitForIdle()

        #expect(await transcription.calls == 1)
        #expect(await coaching.calls == 0)
        #expect(await coordinator.snapshot().durable.state == .noSpeech)
        #expect(await store.states.contains(.queued))
    }

    @Test("retrying coaching never retranscribes audio")
    func retryingCoachingNeverRetranscribesAudio() async throws {
        let transcription = TranscriptionSpy(events: [])
        let coaching = CoachingSpy()
        let coordinator = VoiceSessionCoordinator(
            initial: turn(state: .recoverableFailure, stage: .coaching, transcript: "accepted"),
            checkpoints: CheckpointSpy(), transcription: transcription, coaching: coaching,
            connectivity: ConnectivitySpy(available: true), reconciliation: ReconciliationSpy(.safeToRetry),
            capture: NoopCapture(), audio: NoopAudio(),
            retryScheduler: .init(maximumAttempts: 0)
        )

        try await coordinator.recoverIfAuthorized()
        await coordinator.waitForIdle()

        #expect(await transcription.calls == 0)
        #expect(await coaching.calls == 1)
    }

    @Test("ambiguous paid work waits for explicit confirmation")
    func ambiguousPaidWorkWaitsForConfirmation() async throws {
        let coaching = CoachingSpy()
        let coordinator = VoiceSessionCoordinator(
            initial: turn(state: .recoverableFailure, stage: .coaching, transcript: "accepted"),
            checkpoints: CheckpointSpy(), transcription: TranscriptionSpy(events: []), coaching: coaching,
            connectivity: ConnectivitySpy(available: true), reconciliation: ReconciliationSpy(.ambiguous),
            capture: NoopCapture(), audio: NoopAudio()
        )

        try await coordinator.recoverIfAuthorized()

        #expect(await coaching.calls == 0)
        #expect(await coordinator.snapshot().durable.state == .resumeRequiresConfirmation)
        #expect(await coordinator.snapshot().requiresResumeConfirmation)
    }
}

@Suite("Voice retry scheduler")
struct VoiceRetrySchedulerTests {
    @Test("backoff is bounded and deterministic with injected jitter")
    func boundedBackoff() {
        let scheduler = VoiceRetryScheduler(baseDelay: 1, maximumDelay: 8, maximumAttempts: 4, jitter: { _ in 0 })
        #expect(scheduler.delay(forAttempt: 0) == 1)
        #expect(scheduler.delay(forAttempt: 3) == 8)
        #expect(scheduler.delay(forAttempt: 4) == nil)
    }
}

private enum IDs {
    static let turn = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    static let conversation = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    static let transcription = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    static let coaching = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
}

private func turn(state: VoiceTurnState, stage: VoiceTurnStage, transcript: String? = nil) -> VoiceTurnRecord {
    VoiceTurnRecord(
        id: IDs.turn.uuidString, conversationID: IDs.conversation.uuidString,
        transcriptionRequestID: IDs.transcription.uuidString, transcriptionIdempotencyKey: "transcription-1",
        coachingRequestID: IDs.coaching.uuidString, coachingIdempotencyKey: "coaching-1",
        state: state, stage: stage, audioFileID: "audio-1", audioSHA256: "abc", audioDurationMS: 1000,
        acceptedTranscript: transcript, createdAtMS: 1, updatedAtMS: 1
    )
}

private actor CheckpointSpy: VoiceTurnCheckpointing {
    private(set) var states: [VoiceTurnState] = []
    func checkpoint(
        _ record: VoiceTurnRecord,
        messages: [MessageRecord],
        cleanup: VoiceTurnCleanup?
    ) async throws { states.append(record.state) }
}

private actor ConnectivitySpy: ConnectivityMonitoring {
    private var available: Bool
    init(available: Bool) { self.available = available }
    func isAvailable() async -> Bool { available }
    func setAvailable(_ value: Bool) { available = value }
}

private actor TranscriptionSpy: VoiceTranscriptionRunning {
    private let events: [TranscriptionStreamEvent]
    private(set) var calls = 0
    init(events: [TranscriptionStreamEvent]) { self.events = events }
    func stream(for turn: VoiceTurnRecord) async throws -> AsyncThrowingStream<TranscriptionStreamEvent, Error> {
        calls += 1
        return AsyncThrowingStream<TranscriptionStreamEvent, Error> { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}

private actor CoachingSpy: VoiceCoachingRunning {
    private(set) var calls = 0
    func stream(for turn: VoiceTurnRecord) async throws -> AsyncThrowingStream<CoachingStreamEvent, Error> {
        calls += 1
        return AsyncThrowingStream<CoachingStreamEvent, Error> { continuation in
            continuation.yield(.failed(requestId: IDs.coaching, sequence: 0, code: .coachingUnavailable, retryable: true))
            continuation.finish()
        }
    }
}

private struct ReconciliationSpy: CoachingReconciliationLookingUp {
    let result: CoachingReconciliationResult
    init(_ result: CoachingReconciliationResult) { self.result = result }
    func reconcile(requestID: UUID) async throws -> CoachingReconciliationResult { result }
    func authorizeRetry(requestID: UUID) async throws {}
}

private actor NoopCapture: VoiceCaptureControlling {
    func start(turnID: UUID) async throws {}
    func pause(turnID: UUID) async throws {}
    func resume(turnID: UUID) async throws {}
    func finalize(turnID: UUID) async throws -> FinalizedVoiceAudio {
        .init(fileID: "audio-1", sha256: "abc", durationMS: 1_000)
    }
    func cancel(turnID: UUID) async throws {}
}

private actor NoopAudio: VoiceAudioDeleting {
    func delete(fileID: String) async throws {}
}
