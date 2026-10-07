import Foundation
import GRDB
import Testing
@testable import TaisaStorage

private struct VoiceTurnKeys: DatabaseKeyStore {
    let key = Data(repeating: 0x37, count: 32)
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws {}
}

@Suite(.serialized)
struct ConversationTurnRepositoryTests {
    private let conversationID = "00000000-0000-0000-0000-000000000001"
    private let turnID = "00000000-0000-0000-0000-000000000002"
    private let deviceID = "00000000-0000-0000-0000-000000000003"

    @Test func checkpointQueuesTurnBeforeAnyTransportStarts() async throws {
        let fixture = try await makeFixture()
        defer { fixture.remove() }
        let repository = ConversationTurnRepository(store: fixture.store)
        let turn = queuedTurn()
        let context = MutationContext(
            id: "00000000-0000-0000-0000-000000000004",
            deviceID: deviceID,
            timestamp: 10
        )

        try await repository.checkpoint(turn, messages: [], cleanup: nil, context: context)

        #expect(try await repository.turn(id: turnID) == turn)
        let journal = try await ChangeJournal(store: fixture.store).pending(limit: 10)
        #expect(journal.count == 1)
        #expect(journal.first?.entityType == "voice_turn")
        #expect(journal.first?.entityID == turnID)
    }

    @Test func completedTurnCommitsBothMessagesAndReceiptAtomically() async throws {
        let fixture = try await makeFixture()
        defer { fixture.remove() }
        let repository = ConversationTurnRepository(store: fixture.store)
        let user = MessageRecord(
            id: "00000000-0000-0000-0000-000000000011", conversationID: conversationID,
            role: "user", body: "I led the critique.", createdAtMS: 20
        )
        let assistant = MessageRecord(
            id: "00000000-0000-0000-0000-000000000012", conversationID: conversationID,
            role: "assistant", body: "What changed?", createdAtMS: 21
        )
        let completed = queuedTurn().completing(
            acceptedTranscript: user.body,
            transcriptionReceipt: "transcript-receipt",
            coachingReceipt: "coaching-receipt",
            userMessageID: user.id,
            assistantMessageID: assistant.id,
            updatedAtMS: 22
        )
        let context = MutationContext(
            id: "00000000-0000-0000-0000-000000000013",
            deviceID: deviceID,
            timestamp: 22
        )

        try await repository.checkpoint(
            completed,
            messages: [user, assistant],
            cleanup: VoiceTurnCleanup(audioFileID: "audio-private-path", completedAtMS: 22),
            context: context
        )

        #expect(try await repository.turn(id: turnID)?.coachingReceipt == "coaching-receipt")
        let counts = try await fixture.store.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT count(*) FROM messages") ?? 0,
                try Int.fetchOne(db, sql: "SELECT count(*) FROM voice_turns WHERE state = 'completed'") ?? 0
            )
        }
        #expect(counts.0 == 2)
        #expect(counts.1 == 1)
    }

    @Test func checkpointRollsBackTurnMessagesAndCleanupTogether() async throws {
        let fixture = try await makeFixture()
        defer { fixture.remove() }
        let repository = ConversationTurnRepository(store: fixture.store)
        let duplicate = MessageRecord(
            id: "00000000-0000-0000-0000-000000000021", conversationID: conversationID,
            role: "user", body: "duplicate", createdAtMS: 30
        )
        let context = MutationContext(
            id: "00000000-0000-0000-0000-000000000022",
            deviceID: deviceID,
            timestamp: 30
        )

        await #expect(throws: Error.self) {
            try await repository.checkpoint(
                queuedTurn(), messages: [duplicate, duplicate],
                cleanup: VoiceTurnCleanup(audioFileID: "audio-private-path", completedAtMS: nil),
                context: context
            )
        }
        let counts = try await fixture.store.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT count(*) FROM voice_turns") ?? 0,
                try Int.fetchOne(db, sql: "SELECT count(*) FROM messages") ?? 0,
                try Int.fetchOne(db, sql: "SELECT count(*) FROM audio_cleanup_queue") ?? 0,
                try Int.fetchOne(db, sql: "SELECT count(*) FROM outbox") ?? 0
            )
        }
        #expect(counts == (0, 0, 0, 0))
    }

    @Test func journalProjectionExcludesAudioReferencesAndEphemeralText() async throws {
        let fixture = try await makeFixture()
        defer { fixture.remove() }
        let repository = ConversationTurnRepository(store: fixture.store)
        let context = MutationContext(
            id: "00000000-0000-0000-0000-000000000031",
            deviceID: deviceID,
            timestamp: 40
        )
        try await repository.checkpoint(queuedTurn(), messages: [], cleanup: nil, context: context)

        let payload = try #require(try await ChangeJournal(store: fixture.store).pending(limit: 1).first?.payload)
        let text = String(decoding: payload, as: UTF8.self)
        #expect(!text.contains("audio-private-path"))
        #expect(!text.contains("partialDelta"))
        #expect(!text.contains("audioFileID"))
    }

    @Test func identicalCheckpointReplayIsIdempotent() async throws {
        let fixture = try await makeFixture(); defer { fixture.remove() }
        let repository = ConversationTurnRepository(store: fixture.store)
        let context = MutationContext(
            id: "00000000-0000-0000-0000-000000000051",
            deviceID: deviceID, timestamp: 50
        )

        try await repository.checkpoint(queuedTurn(), messages: [], cleanup: nil, context: context)
        try await repository.checkpoint(queuedTurn(), messages: [], cleanup: nil, context: context)

        #expect(try await ChangeJournal(store: fixture.store).pending(limit: 10).count == 1)
    }

    @Test func requestIdentityCannotChangeAndTerminalStateCannotReactivate() async throws {
        let fixture = try await makeFixture(); defer { fixture.remove() }
        let repository = ConversationTurnRepository(store: fixture.store)
        let initial = queuedTurn()
        try await repository.checkpoint(
            initial, messages: [], cleanup: nil,
            context: MutationContext(
                id: "00000000-0000-0000-0000-000000000061",
                deviceID: deviceID, timestamp: 60
            )
        )
        let changedIdentity = VoiceTurnRecord(
            id: initial.id, conversationID: initial.conversationID,
            transcriptionRequestID: "00000000-0000-0000-0000-000000000062",
            transcriptionIdempotencyKey: initial.transcriptionIdempotencyKey,
            coachingRequestID: initial.coachingRequestID,
            coachingIdempotencyKey: initial.coachingIdempotencyKey,
            state: .transcribing, stage: .transcription,
            audioFileID: initial.audioFileID, audioSHA256: initial.audioSHA256,
            audioDurationMS: initial.audioDurationMS, cleanupState: initial.cleanupState,
            createdAtMS: initial.createdAtMS, updatedAtMS: 61
        )
        await #expect(throws: RepositoryError.immutableRecord) {
            try await repository.checkpoint(
                changedIdentity, messages: [], cleanup: nil,
                context: MutationContext(
                    id: "00000000-0000-0000-0000-000000000063",
                    deviceID: deviceID, timestamp: 61
                )
            )
        }

        let terminal = VoiceTurnRecord(
            id: initial.id, conversationID: initial.conversationID,
            transcriptionRequestID: initial.transcriptionRequestID,
            transcriptionIdempotencyKey: initial.transcriptionIdempotencyKey,
            coachingRequestID: initial.coachingRequestID,
            coachingIdempotencyKey: initial.coachingIdempotencyKey,
            state: .noSpeech, stage: .finished,
            retryCount: initial.retryCount, cleanupState: .completed,
            createdAtMS: initial.createdAtMS, updatedAtMS: 62
        )
        try await repository.checkpoint(
            terminal, messages: [], cleanup: nil,
            context: MutationContext(
                id: "00000000-0000-0000-0000-000000000066",
                deviceID: deviceID, timestamp: 62
            )
        )
        await #expect(throws: RepositoryError.immutableRecord) {
            try await repository.checkpoint(
                initial, messages: [], cleanup: nil,
                context: MutationContext(
                    id: "00000000-0000-0000-0000-000000000067",
                    deviceID: deviceID, timestamp: 63
                )
            )
        }
    }

    @Test func latestResumableTurnRestoresActiveWorkButIgnoresFinishedHistory() async throws {
        let fixture = try await makeFixture(); defer { fixture.remove() }
        let repository = ConversationTurnRepository(store: fixture.store)
        let active = queuedTurn()
        try await repository.checkpoint(
            active, messages: [], cleanup: nil,
            context: MutationContext(
                id: "00000000-0000-0000-0000-000000000071",
                deviceID: deviceID, timestamp: 70
            )
        )

        #expect(try await repository.latestResumableTurn(conversationID: conversationID) == active)

        let finished = VoiceTurnRecord(
            id: active.id, conversationID: active.conversationID,
            transcriptionRequestID: active.transcriptionRequestID,
            transcriptionIdempotencyKey: active.transcriptionIdempotencyKey,
            coachingRequestID: active.coachingRequestID,
            coachingIdempotencyKey: active.coachingIdempotencyKey,
            state: .noSpeech, stage: .finished,
            cleanupState: .completed,
            createdAtMS: active.createdAtMS, updatedAtMS: 71
        )
        try await repository.checkpoint(
            finished, messages: [], cleanup: nil,
            context: MutationContext(
                id: "00000000-0000-0000-0000-000000000072",
                deviceID: deviceID, timestamp: 71
            )
        )

        #expect(try await repository.latestResumableTurn(conversationID: conversationID) == nil)
    }

    private func queuedTurn() -> VoiceTurnRecord {
        VoiceTurnRecord(
            id: turnID,
            conversationID: conversationID,
            transcriptionRequestID: "00000000-0000-0000-0000-000000000041",
            transcriptionIdempotencyKey: "transcription-key",
            coachingRequestID: "00000000-0000-0000-0000-000000000042",
            coachingIdempotencyKey: "coaching-key",
            state: .queued,
            stage: .transcription,
            audioFileID: "audio-private-path",
            audioSHA256: "audio-fingerprint",
            audioDurationMS: 1_200,
            retryCount: 0,
            cleanupState: .pending,
            createdAtMS: 1,
            updatedAtMS: 1
        )
    }

    private func makeFixture() async throws -> (store: TaisaStore, remove: () -> Void) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let store = try await TaisaStore.open(
            at: directory.appendingPathComponent("store.sqlite"), keyStore: VoiceTurnKeys()
        )
        try await store.write { db in
            try db.execute(
                sql: "INSERT INTO conversations (id, title, created_at_ms, updated_at_ms) VALUES (?, '', 1, 1)",
                arguments: [conversationID]
            )
        }
        return (store, { try? FileManager.default.removeItem(at: directory) })
    }
}
