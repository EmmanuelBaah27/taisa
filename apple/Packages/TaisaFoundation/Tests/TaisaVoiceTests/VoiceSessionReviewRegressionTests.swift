import Foundation
import GRDB
import Testing
import TaisaAudio
import TaisaContracts
import TaisaNetworking
import TaisaStorage
@testable import TaisaVoice

@Suite("Voice review regressions")
struct VoiceSessionReviewRegressionTests {
    @Test("relaunch cleans up a legacy cancelled capture and unlocks the next turn")
    func relaunchRecoversCancelledCapture() async throws {
        let capture = ReviewCaptureSpy()
        let audio = ReviewAudioSpy()
        let initial = VoiceTurnRecord(
            id: ReviewIDs.turn.uuidString,
            conversationID: ReviewIDs.conversation.uuidString,
            transcriptionRequestID: ReviewIDs.transcription.uuidString,
            transcriptionIdempotencyKey: "transcription-1",
            coachingRequestID: ReviewIDs.coaching.uuidString,
            coachingIdempotencyKey: "coaching-1",
            state: .cancelled,
            stage: .capture,
            audioFileID: "00000000-0000-0000-0000-000000000201",
            cleanupState: .pending,
            createdAtMS: 1,
            updatedAtMS: 1
        )
        let coordinator = VoiceSessionCoordinator(
            initial: initial,
            checkpoints: ReviewCheckpointSpy(),
            transcription: ReviewTranscriptionRunner(events: []),
            coaching: ReviewCoachingRunner(events: []),
            connectivity: ReviewConnectivity(),
            reconciliation: ReviewReconciliation(),
            capture: capture,
            audio: audio
        )

        try await coordinator.recoverIfAuthorized()

        #expect(await coordinator.snapshot().durable.state == .discarded)
        #expect(await coordinator.snapshot().durable.stage == .finished)
        #expect(await capture.discarded.isEmpty)
        #expect(await audio.deleted == ["00000000-0000-0000-0000-000000000201"])
    }

    @Test("relaunch finishes local cleanup before connectivity becomes available")
    func relaunchFinishesCleanupWhileOffline() async throws {
        let audio = ReviewAudioSpy()
        let initial = VoiceTurnRecord(
            id: ReviewIDs.turn.uuidString,
            conversationID: ReviewIDs.conversation.uuidString,
            transcriptionRequestID: ReviewIDs.transcription.uuidString,
            transcriptionIdempotencyKey: "transcription-1",
            coachingRequestID: ReviewIDs.coaching.uuidString,
            coachingIdempotencyKey: "coaching-1",
            state: .discarded,
            stage: .cleanup,
            audioFileID: "00000000-0000-0000-0000-000000000201",
            cleanupState: .pending,
            createdAtMS: 1,
            updatedAtMS: 1
        )
        let coordinator = VoiceSessionCoordinator(
            initial: initial,
            checkpoints: ReviewCheckpointSpy(),
            transcription: ReviewTranscriptionRunner(events: []),
            coaching: ReviewCoachingRunner(events: []),
            connectivity: ReviewConnectivity(available: false),
            reconciliation: ReviewReconciliation(),
            capture: ReviewCaptureSpy(),
            audio: audio
        )

        try await coordinator.recoverIfAuthorized()

        #expect(await audio.deleted == ["00000000-0000-0000-0000-000000000201"])
        #expect(await coordinator.snapshot().durable.stage == .finished)
    }

    @Test("recording preparation failure does not leave a fake recording session")
    func preparationFailureFinishesTheTurn() async throws {
        let coordinator = VoiceSessionCoordinator(
            initial: reviewTurn(state: .draft, stage: .capture),
            checkpoints: ReviewCheckpointSpy(),
            transcription: ReviewTranscriptionRunner(events: []),
            coaching: ReviewCoachingRunner(events: []),
            connectivity: ReviewConnectivity(),
            reconciliation: ReviewReconciliation(),
            capture: FailingPrepareCapture(),
            audio: ReviewAudioSpy()
        )

        await #expect(throws: AudioCaptureError.permissionDenied) {
            try await coordinator.send(.startRecording)
        }

        let snapshot = await coordinator.snapshot()
        #expect(snapshot.durable.state == .terminalFailure)
        #expect(snapshot.durable.stage == .finished)
        #expect(snapshot.durable.failureCode == "CAPTURE_PREPARE_FAILED")
    }

    @Test("relaunch terminalizes a checkpointed recording even when prepare never produced a file")
    func relaunchRecoversRecordingWithoutPreparedAudio() async throws {
        let capture = ReviewCaptureSpy()
        let initial = VoiceTurnRecord(
            id: ReviewIDs.turn.uuidString,
            conversationID: ReviewIDs.conversation.uuidString,
            transcriptionRequestID: ReviewIDs.transcription.uuidString,
            transcriptionIdempotencyKey: "transcription-1",
            coachingRequestID: ReviewIDs.coaching.uuidString,
            coachingIdempotencyKey: "coaching-1",
            state: .recording,
            stage: .capture,
            createdAtMS: 1,
            updatedAtMS: 1
        )
        let coordinator = VoiceSessionCoordinator(
            initial: initial,
            checkpoints: ReviewCheckpointSpy(),
            transcription: ReviewTranscriptionRunner(events: []),
            coaching: ReviewCoachingRunner(events: []),
            connectivity: ReviewConnectivity(),
            reconciliation: ReviewReconciliation(),
            capture: capture,
            audio: ReviewAudioSpy()
        )

        try await coordinator.recoverIfAuthorized()

        #expect(await coordinator.snapshot().durable.state == .terminalFailure)
        #expect(await coordinator.snapshot().durable.stage == .finished)
        #expect(await capture.released == [ReviewIDs.turn])
    }

    @Test("coordinator commits terminal history through the encrypted repository")
    func encryptedRepositoryIntegration() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("taisa-voice-review-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(
            at: directory.appendingPathComponent("store.sqlite"),
            keyStore: ReviewDatabaseKeys()
        )
        try await store.write { database in
            try database.execute(
                sql: """
                INSERT INTO conversations (id, title, created_at_ms, updated_at_ms)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [ReviewIDs.conversation.uuidString.lowercased(), "Review", 1, 1]
            )
        }
        let messageIDs = ReviewMessageIDs()
        let audio = ReviewAudioSpy()
        let coordinator = VoiceSessionCoordinator(
            initial: reviewTurn(state: .queued, stage: .transcription),
            checkpoints: RepositoryVoiceTurnCheckpointer(
                repository: ConversationTurnRepository(store: store),
                deviceID: UUID(uuidString: "77777777-7777-4777-8777-777777777777")!,
                nowMS: { 100 }
            ),
            transcription: ReviewTranscriptionRunner(events: [try reviewTranscriptionCompleted()]),
            coaching: ReviewCoachingRunner(events: [
                .completed(
                    requestId: ReviewIDs.coaching, sequence: 0,
                    response: try reviewResponse(), idempotencyReceipt: "receipt-1"
                ),
            ]),
            connectivity: ReviewConnectivity(), reconciliation: ReviewReconciliation(),
            capture: ReviewCaptureSpy(), audio: audio,
            makeMessageID: messageIDs.next, nowMS: { 100 }
        )

        try await coordinator.recoverIfAuthorized()
        await coordinator.waitForIdle()

        let result = try await store.read { database in
            (
                try String.fetchAll(database, sql: "SELECT body FROM messages ORDER BY created_at_ms, role"),
                try String.fetchOne(database, sql: "SELECT state FROM voice_turns LIMIT 1"),
                try Int.fetchOne(database, sql: "SELECT count(*) FROM audio_cleanup_queue") ?? -1
            )
        }
        #expect(Set(result.0) == Set(["I led the critique.", "What changed?"]))
        #expect(result.1 == "completed")
        #expect(result.2 == 0)
    }

    @Test("terminal transcript and coaching bodies checkpoint atomically before audio cleanup")
    func terminalBodiesPersistBeforeCleanup() async throws {
        let checkpoints = ReviewCheckpointSpy()
        let audio = ReviewAudioSpy()
        let capture = ReviewCaptureSpy()
        let messageIDs = ReviewMessageIDs()
        let coordinator = VoiceSessionCoordinator(
            initial: reviewTurn(state: .queued, stage: .transcription),
            checkpoints: checkpoints,
            transcription: ReviewTranscriptionRunner(events: [try reviewTranscriptionCompleted()]),
            coaching: ReviewCoachingRunner(events: [
                .completed(
                    requestId: ReviewIDs.coaching, sequence: 0,
                    response: try reviewResponse(), idempotencyReceipt: "receipt-1"
                ),
            ]),
            connectivity: ReviewConnectivity(),
            reconciliation: ReviewReconciliation(),
            capture: capture,
            audio: audio,
            makeMessageID: messageIDs.next
        )

        try await coordinator.recoverIfAuthorized()
        await coordinator.waitForIdle()

        #expect(await checkpoints.messageBodies == ["I led the critique.", "What changed?"])
        #expect(await audio.deleted == ["audio-1"])
        #expect(await capture.released == [ReviewIDs.turn])
        #expect(await coordinator.snapshot().durable.stage == .finished)
    }

    @Test("discard during capture stops and deletes the recorder-owned file")
    func discardDuringCaptureUsesCaptureDiscard() async throws {
        let capture = ReviewCaptureSpy()
        let coordinator = VoiceSessionCoordinator(
            initial: reviewTurn(state: .recording, stage: .capture),
            checkpoints: ReviewCheckpointSpy(),
            transcription: ReviewTranscriptionRunner(events: []),
            coaching: ReviewCoachingRunner(events: []),
            connectivity: ReviewConnectivity(), reconciliation: ReviewReconciliation(),
            capture: capture, audio: ReviewAudioSpy()
        )

        try await coordinator.send(.discard)

        #expect(await capture.discarded == [ReviewIDs.turn])
        #expect(await capture.cancelled.isEmpty)
        #expect(await capture.released == [ReviewIDs.turn])
        #expect(await coordinator.snapshot().durable.stage == .finished)
    }

    @Test("persisted transitions receive monotonic update timestamps")
    func transitionTimestampsAdvance() async throws {
        let checkpoints = ReviewCheckpointSpy()
        let coordinator = VoiceSessionCoordinator(
            initial: reviewTurn(state: .draft, stage: .capture),
            checkpoints: checkpoints,
            transcription: ReviewTranscriptionRunner(events: []),
            coaching: ReviewCoachingRunner(events: []),
            connectivity: ReviewConnectivity(), reconciliation: ReviewReconciliation(),
            capture: ReviewCaptureSpy(), audio: ReviewAudioSpy(), nowMS: { 100 }
        )

        try await coordinator.send(.startRecording)
        try await coordinator.send(.pauseRecording)

        #expect(await checkpoints.updatedAtValues == [100, 101, 102])
        #expect(await coordinator.snapshot().durable.updatedAtMS == 102)
        #expect(await coordinator.snapshot().durable.audioFileID == "00000000-0000-0000-0000-000000000201")
    }

    @Test("capture lifecycle pause is checkpointed into durable session state")
    func lifecyclePauseUpdatesDurableState() async throws {
        let capture = ReviewCaptureSpy()
        let coordinator = VoiceSessionCoordinator(
            initial: reviewTurn(state: .draft, stage: .capture),
            checkpoints: ReviewCheckpointSpy(),
            transcription: ReviewTranscriptionRunner(events: []),
            coaching: ReviewCoachingRunner(events: []),
            connectivity: ReviewConnectivity(), reconciliation: ReviewReconciliation(),
            capture: capture, audio: ReviewAudioSpy()
        )

        try await coordinator.send(.startRecording)
        await capture.emit(.paused(turnID: ReviewIDs.turn, reason: .interruption))
        for _ in 0..<20 where await coordinator.snapshot().durable.state != .paused {
            await Task.yield()
        }

        #expect(await coordinator.snapshot().durable.state == .paused)
    }

    @Test("relaunch of interrupted capture deletes retained audio and unlocks the next turn")
    func interruptedCaptureRelaunchCleansUp() async throws {
        let audio = ReviewAudioSpy()
        let capture = ReviewCaptureSpy()
        let coordinator = VoiceSessionCoordinator(
            initial: reviewTurn(state: .paused, stage: .capture),
            checkpoints: ReviewCheckpointSpy(),
            transcription: ReviewTranscriptionRunner(events: []),
            coaching: ReviewCoachingRunner(events: []),
            connectivity: ReviewConnectivity(), reconciliation: ReviewReconciliation(),
            capture: capture, audio: audio
        )

        try await coordinator.recoverIfAuthorized()

        #expect(await audio.deleted == ["audio-1"])
        #expect(await capture.released == [ReviewIDs.turn])
        #expect(await coordinator.snapshot().durable.state == .terminalFailure)
        #expect(await coordinator.snapshot().durable.stage == .finished)
    }

    @Test("media services reset becomes terminal cleanup instead of fake resumable pause")
    func mediaResetCleansUpCapture() async throws {
        let audio = ReviewAudioSpy()
        let capture = ReviewCaptureSpy()
        let coordinator = VoiceSessionCoordinator(
            initial: reviewTurn(state: .draft, stage: .capture),
            checkpoints: ReviewCheckpointSpy(),
            transcription: ReviewTranscriptionRunner(events: []),
            coaching: ReviewCoachingRunner(events: []),
            connectivity: ReviewConnectivity(), reconciliation: ReviewReconciliation(),
            capture: capture, audio: audio
        )

        try await coordinator.send(.startRecording)
        await capture.emit(.blocked(turnID: ReviewIDs.turn, reason: .mediaServicesReset))
        for _ in 0..<40 where await coordinator.snapshot().durable.stage != .finished {
            await Task.yield()
        }

        #expect(await capture.discarded == [ReviewIDs.turn])
        #expect(await coordinator.snapshot().durable.failureCode == "MEDIA_SERVICES_RESET")
        #expect(await coordinator.snapshot().durable.stage == .finished)
    }

    @Test("ambiguous transcription waits for explicit owner-authorized retry")
    func ambiguousTranscriptionRequiresConfirmation() async throws {
        let reconciliation = ReviewTranscriptionReconciliation(.ambiguous)
        let coordinator = VoiceSessionCoordinator(
            initial: reviewTurn(state: .queued, stage: .transcription),
            checkpoints: ReviewCheckpointSpy(),
            transcription: ReconciliationRequiredTranscriptionRunner(),
            transcriptionReconciliation: reconciliation,
            coaching: ReviewCoachingRunner(events: []),
            connectivity: ReviewConnectivity(), reconciliation: ReviewReconciliation(),
            capture: ReviewCaptureSpy(), audio: ReviewAudioSpy()
        )

        try await coordinator.recoverIfAuthorized()
        await coordinator.waitForIdle()
        #expect(await coordinator.snapshot().durable.state == .resumeRequiresConfirmation)

        try await coordinator.send(.confirmResume)
        await coordinator.waitForIdle()
        #expect(await reconciliation.authorizeCalls == 1)
    }

    @Test("cancel stops an active transcription stream and suppresses later events")
    func cancellationStopsStream() async throws {
        let transcription = BlockingReviewTranscriptionRunner()
        let coordinator = VoiceSessionCoordinator(
            initial: reviewTurn(state: .queued, stage: .transcription),
            checkpoints: ReviewCheckpointSpy(), transcription: transcription,
            coaching: ReviewCoachingRunner(events: []), connectivity: ReviewConnectivity(),
            reconciliation: ReviewReconciliation(), capture: ReviewCaptureSpy(), audio: ReviewAudioSpy()
        )

        try await coordinator.recoverIfAuthorized()
        await transcription.waitUntilStarted()
        try await coordinator.send(.cancel)
        await coordinator.waitForIdle()
        await transcription.waitUntilCancelled()

        #expect(await transcription.wasCancelled)
        #expect(await coordinator.snapshot().durable.state == .cancelled)
    }

    @Test("explicit confirmation authorizes ambiguous work before retrying coaching")
    func confirmationAuthorizesRetry() async throws {
        let reconciliation = ReviewReconciliation()
        let coaching = ReviewCoachingRunner(events: [
            .failed(
                requestId: ReviewIDs.coaching, sequence: 0,
                code: .coachingUnavailable, retryable: true
            ),
        ])
        let coordinator = VoiceSessionCoordinator(
            initial: reviewTurn(
                state: .resumeRequiresConfirmation, stage: .coaching,
                transcript: "accepted"
            ),
            checkpoints: ReviewCheckpointSpy(), transcription: ReviewTranscriptionRunner(events: []),
            coaching: coaching, connectivity: ReviewConnectivity(), reconciliation: reconciliation,
            capture: ReviewCaptureSpy(), audio: ReviewAudioSpy(),
            retryScheduler: .init(maximumAttempts: 0)
        )

        try await coordinator.send(.confirmResume)
        await coordinator.waitForIdle()

        #expect(await reconciliation.authorizeCalls == 1)
        #expect(await coaching.calls == 1)
    }

    @Test("automatic retries durably advance their bounded attempt count")
    func automaticRetriesAreDurableAndBounded() async throws {
        let checkpoints = ReviewCheckpointSpy()
        let coaching = ReviewCoachingRunner(events: [
            .failed(
                requestId: ReviewIDs.coaching, sequence: 0,
                code: .coachingUnavailable, retryable: true
            ),
        ])
        let coordinator = VoiceSessionCoordinator(
            initial: reviewTurn(state: .transcriptClear, stage: .coaching, transcript: "accepted"),
            checkpoints: checkpoints, transcription: ReviewTranscriptionRunner(events: []),
            coaching: coaching, connectivity: ReviewConnectivity(),
            reconciliation: ReviewReconciliation(), capture: ReviewCaptureSpy(),
            audio: ReviewAudioSpy(),
            retryScheduler: .init(baseDelay: 0, maximumDelay: 0, maximumAttempts: 2),
            retrySleeper: ImmediateReviewSleeper(), nowMS: { 500 }
        )

        try await coordinator.recoverIfAuthorized()
        await coordinator.waitForIdle()

        #expect(await coaching.calls == 3)
        #expect(await coordinator.snapshot().durable.retryCount == 2)
        #expect(await coordinator.snapshot().durable.state == .terminalFailure)
        #expect(await checkpoints.retryCounts.contains(1))
        #expect(await checkpoints.retryCounts.contains(2))
    }
}

private enum ReviewIDs {
    static let turn = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    static let conversation = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    static let transcription = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    static let coaching = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
}

private final class ReviewMessageIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var values = [
        "55555555-5555-4555-8555-555555555555",
        "66666666-6666-4666-8666-666666666666",
    ]
    func next() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        return UUID(uuidString: values.removeFirst())!
    }
}

private func reviewTurn(
    state: VoiceTurnState,
    stage: VoiceTurnStage,
    transcript: String? = nil
) -> VoiceTurnRecord {
    VoiceTurnRecord(
        id: ReviewIDs.turn.uuidString, conversationID: ReviewIDs.conversation.uuidString,
        transcriptionRequestID: ReviewIDs.transcription.uuidString,
        transcriptionIdempotencyKey: "transcription-1",
        coachingRequestID: ReviewIDs.coaching.uuidString,
        coachingIdempotencyKey: "coaching-1", state: state, stage: stage,
        audioFileID: "audio-1", audioSHA256: "abc", audioDurationMS: 1_000,
        acceptedTranscript: transcript, createdAtMS: 1, updatedAtMS: 1
    )
}

private func reviewResponse() throws -> CoachingResponse {
    try JSONDecoder().decode(CoachingResponse.self, from: Data("""
    {"requestId":"44444444-4444-4444-8444-444444444444","reply":"What changed?","mode":"coach","relevance":"career-relevant","contextSufficiency":"sufficient","stance":"nudge","proposals":[],"usage":{"provider":"anthropic","model":"fixture","estimatedCostUsd":0}}
    """.utf8))
}

private func reviewTranscriptionCompleted() throws -> TranscriptionStreamEvent {
    try JSONDecoder().decode(TranscriptionStreamEvent.self, from: Data("""
    {"type":"transcript.completed","requestId":"33333333-3333-4333-8333-333333333333","sequence":0,"transcript":"I led the critique.","durationSeconds":1,"quality":"clear","usage":{"provider":"openai","model":"fixture","audioSeconds":1,"estimatedCostUsd":0}}
    """.utf8))
}

private actor ReviewCheckpointSpy: VoiceTurnCheckpointing {
    private(set) var messageBodies: [String] = []
    private(set) var retryCounts: [Int] = []
    private(set) var updatedAtValues: [Int64] = []
    func checkpoint(
        _ record: VoiceTurnRecord,
        messages: [MessageRecord],
        cleanup: VoiceTurnCleanup?
    ) async throws {
        messageBodies.append(contentsOf: messages.map(\.body))
        retryCounts.append(record.retryCount)
        updatedAtValues.append(record.updatedAtMS)
    }
}

private struct ImmediateReviewSleeper: VoiceRetrySleeping {
    func sleep(for seconds: TimeInterval) async throws {}
}

private actor ReviewAudioSpy: VoiceAudioDeleting {
    private(set) var deleted: [String] = []
    func delete(fileID: String) async throws { deleted.append(fileID) }
}

private actor ReviewCaptureSpy: VoiceCaptureControlling {
    private let eventStream: AsyncStream<AudioCaptureEvent>
    private let eventContinuation: AsyncStream<AudioCaptureEvent>.Continuation
    private(set) var cancelled: [UUID] = []
    private(set) var discarded: [UUID] = []
    private(set) var released: [UUID] = []
    init() {
        (eventStream, eventContinuation) = AsyncStream.makeStream(
            of: AudioCaptureEvent.self, bufferingPolicy: .bufferingNewest(8)
        )
    }
    func events() -> AsyncStream<AudioCaptureEvent> { eventStream }
    func emit(_ event: AudioCaptureEvent) { eventContinuation.yield(event) }
    func prepare(turnID: UUID) async throws -> String {
        "00000000-0000-0000-0000-000000000201"
    }
    func start(turnID: UUID) async throws {}
    func pause(turnID: UUID) async throws {}
    func resume(turnID: UUID) async throws {}
    func finalize(turnID: UUID) async throws -> FinalizedVoiceAudio {
        .init(fileID: "audio-1", sha256: "abc", durationMS: 1_000)
    }
    func cancel(turnID: UUID) async throws { cancelled.append(turnID) }
    func discard(turnID: UUID) async throws { discarded.append(turnID) }
    func release(turnID: UUID) async throws { released.append(turnID) }
}

private actor FailingPrepareCapture: VoiceCaptureControlling {
    func events() -> AsyncStream<AudioCaptureEvent> { AsyncStream { $0.finish() } }
    func prepare(turnID: UUID) async throws -> String { throw AudioCaptureError.permissionDenied }
    func start(turnID: UUID) async throws {}
    func pause(turnID: UUID) async throws {}
    func resume(turnID: UUID) async throws {}
    func finalize(turnID: UUID) async throws -> FinalizedVoiceAudio {
        throw AudioCaptureError.audioNotFinalized
    }
    func cancel(turnID: UUID) async throws {}
    func discard(turnID: UUID) async throws {}
    func release(turnID: UUID) async throws {}
}

private actor ReviewTranscriptionRunner: VoiceTranscriptionRunning {
    let events: [TranscriptionStreamEvent]
    init(events: [TranscriptionStreamEvent]) { self.events = events }
    func stream(for turn: VoiceTurnRecord) async throws -> AsyncThrowingStream<TranscriptionStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}

private actor ReconciliationRequiredTranscriptionRunner: VoiceTranscriptionRunning {
    func stream(
        for turn: VoiceTurnRecord
    ) async throws -> AsyncThrowingStream<TranscriptionStreamEvent, Error> {
        throw StreamTransportError.reconciliationRequired
    }
}

private actor ReviewTranscriptionReconciliation: TranscriptionReconciliationLookingUp {
    let result: TranscriptionReconciliationResult
    private(set) var authorizeCalls = 0
    init(_ result: TranscriptionReconciliationResult) { self.result = result }
    func reconcile(requestID: UUID) async throws -> TranscriptionReconciliationResult { result }
    func authorizeRetry(requestID: UUID) async throws { authorizeCalls += 1 }
}

private actor BlockingReviewTranscriptionRunner: VoiceTranscriptionRunning {
    private(set) var wasCancelled = false
    private var started = false
    func stream(for turn: VoiceTurnRecord) async throws -> AsyncThrowingStream<TranscriptionStreamEvent, Error> {
        started = true
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { @Sendable _ in
                Task { await self.markCancelled() }
            }
        }
    }
    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }
    func waitUntilCancelled() async {
        for _ in 0..<1_000 where !wasCancelled { await Task.yield() }
    }
    private func markCancelled() { wasCancelled = true }
}

private actor ReviewCoachingRunner: VoiceCoachingRunning {
    let events: [CoachingStreamEvent]
    private(set) var calls = 0
    init(events: [CoachingStreamEvent]) { self.events = events }
    func stream(for turn: VoiceTurnRecord) async throws -> AsyncThrowingStream<CoachingStreamEvent, Error> {
        calls += 1
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}

private actor ReviewConnectivity: ConnectivityMonitoring {
    private let available: Bool
    init(available: Bool = true) { self.available = available }
    func isAvailable() async -> Bool { available }
}

private actor ReviewReconciliation: CoachingReconciliationLookingUp {
    private(set) var authorizeCalls = 0
    func reconcile(requestID: UUID) async throws -> CoachingReconciliationResult { .ambiguous }
    func authorizeRetry(requestID: UUID) async throws { authorizeCalls += 1 }
}

private actor ReviewDatabaseKeys: DatabaseKeyStore {
    private let key = Data(repeating: 0x42, count: 32)
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws {}
}
