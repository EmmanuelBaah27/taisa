import Foundation
import Testing
import TaisaAudio
import TaisaConversations
import TaisaContracts
import TaisaStorage
@testable import TaisaVoice

@Suite("Voice session coordinator")
struct VoiceSessionCoordinatorTests {
    @Test("snapshot distinguishes empty short sendable and durable processing capture")
    func snapshotDistinguishesCaptureDisposition() async throws {
        let capture = SnapshotCapture(elapsedMilliseconds: 0)
        let coordinator = VoiceSessionCoordinator(
            initial: turn(state: .recording, stage: .capture),
            checkpoints: CheckpointSpy(), transcription: TranscriptionSpy(events: []),
            coaching: CoachingSpy(), connectivity: ConnectivitySpy(available: true),
            reconciliation: ReconciliationSpy(.safeToRetry), capture: capture, audio: NoopAudio()
        )

        #expect(await coordinator.snapshot().capture.disposition == .empty)
        await capture.setElapsedMilliseconds(999)
        #expect(await coordinator.snapshot().capture.disposition == .shortCapture)
        await capture.setElapsedMilliseconds(1_000)
        #expect(await coordinator.snapshot().capture.disposition == .sendable)

        let processing = VoiceSessionCoordinator(
            initial: turn(state: .queued, stage: .transcription),
            checkpoints: CheckpointSpy(), transcription: TranscriptionSpy(events: []),
            coaching: CoachingSpy(), connectivity: ConnectivitySpy(available: false),
            reconciliation: ReconciliationSpy(.safeToRetry), capture: capture, audio: NoopAudio()
        )
        #expect(await processing.snapshot().capture.disposition == .durableProcessing)
    }

    @Test("explicit retry restarts terminal coaching without retranscribing")
    func explicitRetryRestartsTerminalCoachingWithoutRetranscribing() async throws {
        let transcription = TranscriptionSpy(events: [])
        let coaching = SuccessfulCoachingSpy()
        let failed = turn(state: .terminalFailure, stage: .finished, transcript: "accepted")
        let coordinator = VoiceSessionCoordinator(
            initial: failed,
            checkpoints: CheckpointSpy(), transcription: transcription, coaching: coaching,
            connectivity: ConnectivitySpy(available: true), reconciliation: ReconciliationSpy(.safeToRetry),
            capture: NoopCapture(), audio: NoopAudio()
        )

        try await coordinator.restartFailedCoaching(with: replacementTurn(from: failed))
        await coordinator.waitForIdle()

        #expect(await transcription.calls == 0)
        #expect(await coaching.calls == 1)
        #expect(await coordinator.snapshot().durable.state == .completed)
    }

    @Test("safe server state restarts ambiguous coaching with a fresh identity")
    func safeServerStateRestartsAmbiguousCoaching() async throws {
        let transcription = TranscriptionSpy(events: [])
        let coaching = SuccessfulCoachingSpy()
        let ambiguous = turn(
            state: .resumeRequiresConfirmation, stage: .coaching, transcript: "accepted"
        )
        let coordinator = VoiceSessionCoordinator(
            initial: ambiguous,
            checkpoints: CheckpointSpy(), transcription: transcription, coaching: coaching,
            connectivity: ConnectivitySpy(available: true), reconciliation: ReconciliationSpy(.safeToRetry),
            capture: NoopCapture(), audio: NoopAudio()
        )

        try await coordinator.restartCoachingIfServerSafe(with: replacementTurn(from: ambiguous))
        await coordinator.waitForIdle()

        #expect(await transcription.calls == 0)
        #expect(await coaching.calls == 1)
        #expect(await coordinator.snapshot().durable.state == .completed)
    }

    @Test("definitively failed server request restarts ambiguous coaching with a fresh identity")
    func failedServerRequestRestartsAmbiguousCoaching() async throws {
        let transcription = TranscriptionSpy(events: [])
        let coaching = SuccessfulCoachingSpy()
        let ambiguous = turn(
            state: .resumeRequiresConfirmation, stage: .coaching, transcript: "accepted"
        )
        let coordinator = VoiceSessionCoordinator(
            initial: ambiguous,
            checkpoints: CheckpointSpy(), transcription: transcription, coaching: coaching,
            connectivity: ConnectivitySpy(available: true),
            reconciliation: ReconciliationSpy(.failed(code: "PROVIDER_FAILURE", retryable: false)),
            capture: NoopCapture(), audio: NoopAudio()
        )

        try await coordinator.restartCoachingIfServerSafe(with: replacementTurn(from: ambiguous))
        await coordinator.waitForIdle()

        #expect(await transcription.calls == 0)
        #expect(await coaching.calls == 1)
        #expect(await coordinator.snapshot().durable.state == .completed)
    }

    @Test("definitively failed server request restarts a stranded coaching checkpoint")
    func failedServerRequestRestartsStrandedCoaching() async throws {
        let coaching = SuccessfulCoachingSpy()
        let stranded = turn(state: .coaching, stage: .coaching, transcript: "accepted")
        let coordinator = VoiceSessionCoordinator(
            initial: stranded,
            checkpoints: CheckpointSpy(), transcription: TranscriptionSpy(events: []),
            coaching: coaching, connectivity: ConnectivitySpy(available: true),
            reconciliation: ReconciliationSpy(.failed(code: "PROVIDER_FAILURE", retryable: false)),
            capture: NoopCapture(), audio: NoopAudio()
        )

        try await coordinator.restartCoachingIfServerSafe(with: replacementTurn(from: stranded))
        await coordinator.waitForIdle()

        #expect(await coaching.calls == 1)
        #expect(await coordinator.snapshot().durable.state == .completed)
    }

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

    @Test("pause failure preserves the durable paused checkpoint for draft saving")
    func pauseFailurePreservesDurablePausedState() async throws {
        let coordinator = VoiceSessionCoordinator(
            initial: turn(state: .recording, stage: .capture),
            checkpoints: CheckpointSpy(), transcription: TranscriptionSpy(events: []),
            coaching: CoachingSpy(), connectivity: ConnectivitySpy(available: true),
            reconciliation: ReconciliationSpy(.safeToRetry),
            capture: FailingPauseCapture(), audio: NoopAudio()
        )

        await #expect(throws: AudioCaptureError.invalidState) {
            try await coordinator.send(.pauseRecording)
        }
        #expect(await coordinator.snapshot().durable.state == .paused)
    }

    @Test("saving a voice draft preserves finalized audio that can be sent after relaunch")
    func savedVoiceDraftCanSendAfterRelaunch() async throws {
        let capture = DraftCapture()
        let store = CheckpointSpy()
        let coordinator = VoiceSessionCoordinator(
            initial: draftRecordingTurn(), checkpoints: store,
            transcription: TranscriptionSpy(events: [.noSpeech(requestId: IDs.transcription, sequence: 0)]),
            coaching: CoachingSpy(), connectivity: ConnectivitySpy(available: true),
            reconciliation: ReconciliationSpy(.safeToRetry), capture: capture, audio: NoopAudio()
        )

        try await VoiceSessionConversationAdapter(coordinator).saveDraft()
        let saved = await coordinator.snapshot().durable

        #expect(saved.state == .paused)
        #expect(saved.audioFileID == "audio-1")
        #expect(saved.audioSHA256 == "draft-sha")
        #expect(saved.audioDurationMS == 2_000)

        let relaunchedCapture = RejectingFinalizationCapture()
        let relaunched = VoiceSessionCoordinator(
            initial: saved, checkpoints: CheckpointSpy(),
            transcription: TranscriptionSpy(events: [.noSpeech(requestId: IDs.transcription, sequence: 0)]),
            coaching: CoachingSpy(), connectivity: ConnectivitySpy(available: true),
            reconciliation: ReconciliationSpy(.safeToRetry), capture: relaunchedCapture, audio: NoopAudio()
        )

        try await relaunched.sendRecordedAudio()
        await relaunched.waitForIdle()

        #expect(await relaunchedCapture.finalizeCount == 0)
        #expect(await relaunched.snapshot().durable.state == .noSpeech)
    }

    @Test("discarding a restored finalized draft deletes persisted audio without a recorder session")
    func restoredFinalizedDraftDiscardUsesPersistedAudio() async throws {
        let capture = RejectingFinalizationCapture()
        let audio = AudioDeleteSpy()
        let coordinator = VoiceSessionCoordinator(
            initial: finalizedDraftTurn(), checkpoints: CheckpointSpy(),
            transcription: TranscriptionSpy(events: []), coaching: CoachingSpy(),
            connectivity: ConnectivitySpy(available: true),
            reconciliation: ReconciliationSpy(.safeToRetry), capture: capture, audio: audio
        )

        try await VoiceSessionConversationAdapter(coordinator).discardDraft()

        #expect(await capture.discardCount == 0)
        #expect(await audio.deletedFileIDs == ["audio-1"])
        #expect(await coordinator.snapshot().durable.state == .discarded)
        #expect(await coordinator.snapshot().durable.cleanupState == .completed)
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
        acceptedTranscript: transcript,
        transcriptionReceipt: transcript == nil ? nil : IDs.transcription.uuidString,
        userMessageID: transcript == nil ? nil : "77777777-7777-4777-8777-777777777777",
        createdAtMS: 1, updatedAtMS: 1
    )
}

private func draftRecordingTurn() -> VoiceTurnRecord {
    VoiceTurnRecord(
        id: IDs.turn.uuidString, conversationID: IDs.conversation.uuidString,
        transcriptionRequestID: IDs.transcription.uuidString,
        transcriptionIdempotencyKey: "transcription-1",
        coachingRequestID: IDs.coaching.uuidString,
        coachingIdempotencyKey: "coaching-1",
        state: .recording, stage: .capture,
        audioFileID: "audio-1",
        createdAtMS: 1, updatedAtMS: 1
    )
}

private func finalizedDraftTurn() -> VoiceTurnRecord {
    VoiceTurnRecord(
        id: IDs.turn.uuidString, conversationID: IDs.conversation.uuidString,
        transcriptionRequestID: IDs.transcription.uuidString,
        transcriptionIdempotencyKey: "transcription-1",
        coachingRequestID: IDs.coaching.uuidString,
        coachingIdempotencyKey: "coaching-1",
        state: .paused, stage: .capture,
        audioFileID: "audio-1", audioSHA256: "draft-sha", audioDurationMS: 2_000,
        cleanupState: .pending, createdAtMS: 1, updatedAtMS: 2
    )
}

private func replacementTurn(from failed: VoiceTurnRecord) -> VoiceTurnRecord {
    VoiceTurnRecord(
        id: "55555555-5555-4555-8555-555555555555",
        conversationID: failed.conversationID,
        transcriptionRequestID: failed.transcriptionRequestID,
        transcriptionIdempotencyKey: failed.transcriptionIdempotencyKey,
        coachingRequestID: "66666666-6666-4666-8666-666666666666",
        coachingIdempotencyKey: "coaching-retry-1",
        state: .transcriptClear, stage: .coaching,
        acceptedTranscript: failed.acceptedTranscript,
        transcriptionReceipt: failed.transcriptionReceipt,
        userMessageID: nil,
        createdAtMS: 2, updatedAtMS: 2
    )
}

private actor CheckpointSpy: VoiceTurnCheckpointing {
    private(set) var states: [VoiceTurnState] = []
    func checkpoint(
        _ record: VoiceTurnRecord,
        messages: [MessageRecord],
        assistantResponse: AssistantResponseWrite?,
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

private actor SuccessfulCoachingSpy: VoiceCoachingRunning {
    private(set) var calls = 0
    func stream(for turn: VoiceTurnRecord) async throws -> AsyncThrowingStream<CoachingStreamEvent, Error> {
        calls += 1
        let response = try JSONDecoder().decode(CoachingResponse.self, from: Data("""
            {"requestId":"\(turn.coachingRequestID)","reply":"Recovered coaching","mode":"coach","relevance":"career-relevant","contextSufficiency":"sufficient","stance":"nudge","explanation":{"mode":"nudge","evidence":[],"inference":"Recovery can continue.","confidence":"medium","approach":"Resume the bounded response."},"proposal":null,"usage":{"provider":"openai","model":"test","inputTokens":1,"outputTokens":1,"estimatedCostUsd":0},"titleSuggestion":null}
            """.utf8))
        return AsyncThrowingStream<CoachingStreamEvent, Error> { continuation in
            continuation.yield(.completed(
                requestId: UUID(uuidString: turn.coachingRequestID)!, sequence: 0,
                response: response, idempotencyReceipt: "coaching-receipt"
            ))
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
    func events() -> AsyncStream<AudioCaptureEvent> { AsyncStream { $0.finish() } }
    func prepare(turnID: UUID) async throws -> String {
        "00000000-0000-0000-0000-000000000201"
    }
    func start(turnID: UUID) async throws {}
    func pause(turnID: UUID) async throws {}
    func resume(turnID: UUID) async throws {}
    func finalize(turnID: UUID) async throws -> FinalizedVoiceAudio {
        .init(fileID: "audio-1", sha256: "abc", durationMS: 1_000)
    }
    func cancel(turnID: UUID) async throws {}
    func discard(turnID: UUID) async throws {}
    func release(turnID: UUID) async throws {}
}

private actor SnapshotCapture: VoiceCaptureControlling {
    private var elapsedMilliseconds: Int64
    init(elapsedMilliseconds: Int64) { self.elapsedMilliseconds = elapsedMilliseconds }
    func setElapsedMilliseconds(_ value: Int64) { elapsedMilliseconds = value }
    func snapshot(turnID: UUID) async throws -> AudioCaptureSnapshot {
        .init(
            activity: .recording,
            elapsedMilliseconds: elapsedMilliseconds,
            meter: .init(averagePower: -18, peakPower: -6)
        )
    }
    func events() -> AsyncStream<AudioCaptureEvent> { AsyncStream { $0.finish() } }
    func prepare(turnID: UUID) async throws -> String { "audio-1" }
    func start(turnID: UUID) async throws {}
    func pause(turnID: UUID) async throws {}
    func resume(turnID: UUID) async throws {}
    func finalize(turnID: UUID) async throws -> FinalizedVoiceAudio {
        .init(fileID: "audio-1", sha256: "abc", durationMS: elapsedMilliseconds)
    }
    func cancel(turnID: UUID) async throws {}
    func discard(turnID: UUID) async throws {}
    func release(turnID: UUID) async throws {}
}

private actor FailingPauseCapture: VoiceCaptureControlling {
    func events() -> AsyncStream<AudioCaptureEvent> { AsyncStream { $0.finish() } }
    func prepare(turnID: UUID) async throws -> String { IDs.turn.uuidString }
    func start(turnID: UUID) async throws {}
    func pause(turnID: UUID) async throws { throw AudioCaptureError.invalidState }
    func resume(turnID: UUID) async throws {}
    func finalize(turnID: UUID) async throws -> FinalizedVoiceAudio {
        throw AudioCaptureError.audioNotFinalized
    }
    func cancel(turnID: UUID) async throws {}
    func discard(turnID: UUID) async throws {}
    func release(turnID: UUID) async throws {}
}

private actor DraftCapture: VoiceCaptureControlling {
    func events() -> AsyncStream<AudioCaptureEvent> { AsyncStream { $0.finish() } }
    func prepare(turnID: UUID) async throws -> String { "audio-1" }
    func start(turnID: UUID) async throws {}
    func pause(turnID: UUID) async throws {}
    func resume(turnID: UUID) async throws {}
    func finalize(turnID: UUID) async throws -> FinalizedVoiceAudio {
        .init(fileID: "audio-1", sha256: "draft-sha", durationMS: 2_000)
    }
    func cancel(turnID: UUID) async throws {}
    func discard(turnID: UUID) async throws {}
    func release(turnID: UUID) async throws {}
}

private actor RejectingFinalizationCapture: VoiceCaptureControlling {
    private(set) var finalizeCount = 0
    private(set) var discardCount = 0
    func events() -> AsyncStream<AudioCaptureEvent> { AsyncStream { $0.finish() } }
    func prepare(turnID: UUID) async throws -> String { throw AudioCaptureError.invalidState }
    func start(turnID: UUID) async throws { throw AudioCaptureError.invalidState }
    func pause(turnID: UUID) async throws { throw AudioCaptureError.invalidState }
    func resume(turnID: UUID) async throws { throw AudioCaptureError.invalidState }
    func finalize(turnID: UUID) async throws -> FinalizedVoiceAudio {
        finalizeCount += 1
        throw AudioCaptureError.audioNotFinalized
    }
    func cancel(turnID: UUID) async throws {}
    func discard(turnID: UUID) async throws {
        discardCount += 1
        throw AudioCaptureError.invalidState
    }
    func release(turnID: UUID) async throws {}
}

private actor AudioDeleteSpy: VoiceAudioDeleting {
    private(set) var deletedFileIDs: [String] = []
    func delete(fileID: String) async throws { deletedFileIDs.append(fileID) }
}

private actor NoopAudio: VoiceAudioDeleting {
    func delete(fileID: String) async throws {}
}
