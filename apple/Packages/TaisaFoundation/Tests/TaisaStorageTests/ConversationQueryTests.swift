import Foundation
import GRDB
import Testing
@testable import TaisaStorage

private actor ConversationQueryKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}

@Suite(.serialized)
struct ConversationQueryTests {
    private let deviceID = "00000000-0000-0000-0000-000000000099"

    @Test func indexSeparatesDraftsFromNewestCompletedConversations() async throws {
        let fixture = try await makeFixture()
        defer { fixture.remove() }
        let ids = IDs()
        try await fixture.store.write { db in
            try insertConversation(db, id: ids.olderConversation, title: "Older", lifecycle: "completed", updatedAtMS: 20)
            try insertConversation(db, id: ids.newestConversation, title: "Newest", lifecycle: "completed", updatedAtMS: 40)
            try insertConversation(db, id: ids.olderDraftConversation, title: "Older draft", lifecycle: "draft", updatedAtMS: 10)
            try insertConversation(db, id: ids.newestDraftConversation, title: "Newest draft", lifecycle: "draft", updatedAtMS: 30)
            try insertDraft(db, id: ids.olderDraft, conversationID: ids.olderDraftConversation, text: "older", updatedAtMS: 25)
            try insertDraft(db, id: ids.newestDraft, conversationID: ids.newestDraftConversation, text: "newest", updatedAtMS: 50)
        }

        let snapshot = try await ConversationQuery(store: fixture.store).loadIndex()

        #expect(snapshot.drafts.map(\.id) == [ids.newestDraft, ids.olderDraft])
        #expect(snapshot.conversations.map(\.id) == [ids.newestConversation, ids.olderConversation])
    }

    @Test func indexRecoversDraftLifecycleConversationThatAlreadyHasMessages() async throws {
        let fixture = try await makeFixture()
        defer { fixture.remove() }
        let ids = IDs()
        try await fixture.store.write { db in
            try insertConversation(
                db, id: ids.newestDraftConversation,
                title: "Recovered voice conversation", lifecycle: "draft", updatedAtMS: 30
            )
            try insertMessage(
                db, id: ids.originalUser, conversationID: ids.newestDraftConversation,
                role: "user", body: "Persisted transcript", createdAtMS: 31
            )
        }

        let snapshot = try await ConversationQuery(store: fixture.store).loadIndex()

        #expect(snapshot.drafts.isEmpty)
        #expect(snapshot.conversations.map(\.id) == [ids.newestDraftConversation])
    }

    @Test func indexDoesNotDuplicateRecoverableConversationAsDraftAndHistory() async throws {
        let fixture = try await makeFixture()
        defer { fixture.remove() }
        let ids = IDs()
        try await fixture.store.write { db in
            try insertConversation(
                db, id: ids.newestDraftConversation,
                title: "Retryable conversation", lifecycle: "draft", updatedAtMS: 30
            )
            try insertMessage(
                db, id: ids.originalUser, conversationID: ids.newestDraftConversation,
                role: "user", body: "Pending transcript", createdAtMS: 31
            )
            try insertDraft(
                db, id: ids.newestDraft, conversationID: ids.newestDraftConversation,
                text: "Pending transcript", updatedAtMS: 32
            )
        }

        let snapshot = try await ConversationQuery(store: fixture.store).loadIndex()

        #expect(snapshot.drafts.map(\.id) == [ids.newestDraft])
        #expect(snapshot.conversations.isEmpty)
    }

    @Test func indexDoesNotDuplicateCompletedConversationWithRetainedDraft() async throws {
        let fixture = try await makeFixture()
        defer { fixture.remove() }
        let ids = IDs()
        try await fixture.store.write { db in
            try insertConversation(
                db, id: ids.newestDraftConversation,
                title: "Interrupted cleanup", lifecycle: "completed", updatedAtMS: 30
            )
            try insertDraft(
                db, id: ids.newestDraft, conversationID: ids.newestDraftConversation,
                text: "Retained safely", updatedAtMS: 32
            )
        }

        let snapshot = try await ConversationQuery(store: fixture.store).loadIndex()

        #expect(snapshot.drafts.map(\.id) == [ids.newestDraft])
        #expect(snapshot.conversations.isEmpty)
    }

    @Test func indexDoesNotRecoverConversationWhoseOnlyMessageIsDeleted() async throws {
        let fixture = try await makeFixture()
        defer { fixture.remove() }
        let ids = IDs()
        try await fixture.store.write { db in
            try insertConversation(
                db, id: ids.newestDraftConversation,
                title: "Deleted message conversation", lifecycle: "draft", updatedAtMS: 30
            )
            try insertMessage(
                db, id: ids.originalUser, conversationID: ids.newestDraftConversation,
                role: "user", body: "Delete me", createdAtMS: 31
            )
        }
        try await ConversationRepository(store: fixture.store).deleteMessage(
            id: ids.originalUser,
            context: .init(id: ids.deleteMutation, deviceID: deviceID, timestamp: 32)
        )

        let snapshot = try await ConversationQuery(store: fixture.store).loadIndex()

        #expect(snapshot.conversations.isEmpty)
    }

    @Test func correctionSupersedesVisibleExchangeAtomically() async throws {
        let fixture = try await makeFixture()
        defer { fixture.remove() }
        let ids = IDs()
        let repository = ConversationRepository(store: fixture.store)
        try await fixture.store.write { db in
            try insertConversation(db, id: ids.newestConversation, title: "Review", lifecycle: "completed", updatedAtMS: 20)
            try insertMessage(db, id: ids.originalUser, conversationID: ids.newestConversation, role: "user", body: "orignal", createdAtMS: 10)
            try insertMessage(db, id: ids.originalAssistant, conversationID: ids.newestConversation, role: "assistant", body: "old reply", createdAtMS: 11)
        }
        let correction = ConversationCorrection(
            revisionID: ids.revision,
            originalUserMessageID: ids.originalUser,
            originalAssistantMessageID: ids.originalAssistant,
            correctedUserMessage: MessageRecord(
                id: ids.correctedUser, conversationID: ids.newestConversation,
                role: "user", body: "corrected", createdAtMS: 20
            ),
            regeneratedAssistantMessage: MessageRecord(
                id: ids.regeneratedAssistant, conversationID: ids.newestConversation,
                role: "assistant", body: "regenerated", createdAtMS: 21
            ),
            createdAtMS: 20
        )

        try await repository.applyCorrection(
            correction,
            context: .init(id: ids.mutation, deviceID: deviceID, timestamp: 20)
        )
        let snapshot = try await ConversationQuery(store: fixture.store).loadConversation(id: ids.newestConversation)

        #expect(snapshot.visibleMessages.map(\.body) == ["corrected", "regenerated"])
        #expect(snapshot.revisions.count == 1)
        #expect(snapshot.revisions.first?.originalBody == "orignal")
        let retainedBodies = try await fixture.store.read { db in
            try String.fetchAll(db, sql: "SELECT body FROM messages ORDER BY created_at_ms")
        }
        #expect(retainedBodies == ["orignal", "old reply", "corrected", "regenerated"])
    }

    @Test func discardingVoiceDraftQueuesOpaqueAudioCleanup() async throws {
        let fixture = try await makeFixture()
        defer { fixture.remove() }
        let ids = IDs()
        try await fixture.store.write { db in
            try insertConversation(db, id: ids.newestDraftConversation, title: "Draft", lifecycle: "draft", updatedAtMS: 10)
            try db.execute(
                sql: """
                    INSERT INTO voice_turns (
                        id, conversation_id, transcription_request_id, transcription_idempotency_key,
                        coaching_request_id, coaching_idempotency_key, state, stage, audio_file_id,
                        audio_sha256, audio_duration_ms, accepted_transcript, uncertain_transcript,
                        retry_count, next_retry_at_ms, failure_code, transcription_receipt,
                        coaching_receipt, user_message_id, assistant_message_id, cleanup_state,
                        created_at_ms, updated_at_ms
                    ) VALUES (?, ?, ?, ?, ?, ?, 'paused', 'capture', ?, NULL, 1000, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 'notRequired', 1, 1)
                    """,
                arguments: [ids.voiceTurn, ids.newestDraftConversation, ids.transcriptionRequest, ids.transcriptionKey, ids.coachingRequest, ids.coachingKey, ids.audioFile]
            )
            try db.execute(
                sql: "INSERT INTO conversation_drafts VALUES (?, ?, 'voice', NULL, ?, 'saved', 1, 1)",
                arguments: [ids.newestDraft, ids.newestDraftConversation, ids.voiceTurn]
            )
        }

        try await ConversationRepository(store: fixture.store).discardDraft(id: ids.newestDraft)

        let state = try await fixture.store.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT count(*) FROM conversation_drafts WHERE id = ?", arguments: [ids.newestDraft]) ?? -1,
                try String.fetchOne(db, sql: "SELECT state FROM voice_turns WHERE id = ?", arguments: [ids.voiceTurn]),
                try String.fetchOne(db, sql: "SELECT audio_file_id FROM audio_cleanup_queue WHERE turn_id = ?", arguments: [ids.voiceTurn])
            )
        }
        #expect(state.0 == 0)
        #expect(state.1 == "discarded")
        #expect(state.2 == ids.audioFile)
    }

    @Test func renameClaimsUserAuthorityAndDeleteHidesConversation() async throws {
        let fixture = try await makeFixture()
        defer { fixture.remove() }
        let ids = IDs()
        let repository = ConversationRepository(store: fixture.store)
        try await fixture.store.write { db in
            try insertConversation(db, id: ids.newestConversation, title: "Fallback", lifecycle: "completed", updatedAtMS: 10)
        }

        try await repository.rename(
            id: ids.newestConversation,
            title: "My review",
            context: .init(id: ids.mutation, deviceID: deviceID, timestamp: 20)
        )
        #expect(try await repository.get(id: ids.newestConversation)?.title == "My review")
        #expect(try await repository.get(id: ids.newestConversation)?.titleAuthority == .user)

        try await repository.delete(
            id: ids.newestConversation,
            context: .init(id: ids.deleteMutation, deviceID: deviceID, timestamp: 30)
        )
        #expect(try await ConversationQuery(store: fixture.store).loadIndex().conversations.isEmpty)
    }

    @Test func deletingConversationQueuesItsDraftAudioCleanupAtomically() async throws {
        let fixture = try await makeFixture()
        defer { fixture.remove() }
        let ids = IDs()
        try await fixture.store.write { db in
            try insertConversation(db, id: ids.newestDraftConversation, title: "Draft", lifecycle: "draft", updatedAtMS: 10)
            try insertVoiceTurn(db, ids: ids)
            try db.execute(
                sql: "INSERT INTO conversation_drafts VALUES (?, ?, 'voice', NULL, ?, 'saved', 1, 1)",
                arguments: [ids.newestDraft, ids.newestDraftConversation, ids.voiceTurn]
            )
        }

        try await ConversationRepository(store: fixture.store).delete(
            id: ids.newestDraftConversation,
            context: .init(id: ids.deleteMutation, deviceID: deviceID, timestamp: 30)
        )

        let state = try await fixture.store.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT count(*) FROM tombstones WHERE entity_type = 'conversation' AND entity_id = ?", arguments: [ids.newestDraftConversation]) ?? -1,
                try String.fetchOne(db, sql: "SELECT audio_file_id FROM audio_cleanup_queue WHERE turn_id = ?", arguments: [ids.voiceTurn])
            )
        }
        #expect(state.0 == 1)
        #expect(state.1 == ids.audioFile)
    }

    private func makeFixture() async throws -> (store: TaisaStore, remove: () -> Void) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try await TaisaStore.open(
            at: directory.appendingPathComponent("store.sqlite"),
            keyStore: ConversationQueryKeys()
        )
        return (store, { try? FileManager.default.removeItem(at: directory) })
    }
}

private struct IDs {
    let olderConversation = "00000000-0000-0000-0000-000000000001"
    let newestConversation = "00000000-0000-0000-0000-000000000002"
    let olderDraftConversation = "00000000-0000-0000-0000-000000000003"
    let newestDraftConversation = "00000000-0000-0000-0000-000000000004"
    let olderDraft = "00000000-0000-0000-0000-000000000005"
    let newestDraft = "00000000-0000-0000-0000-000000000006"
    let originalUser = "00000000-0000-0000-0000-000000000007"
    let originalAssistant = "00000000-0000-0000-0000-000000000008"
    let correctedUser = "00000000-0000-0000-0000-000000000009"
    let regeneratedAssistant = "00000000-0000-0000-0000-000000000010"
    let revision = "00000000-0000-0000-0000-000000000011"
    let mutation = "00000000-0000-0000-0000-000000000012"
    let deleteMutation = "00000000-0000-0000-0000-000000000013"
    let voiceTurn = "00000000-0000-0000-0000-000000000014"
    let transcriptionRequest = "00000000-0000-0000-0000-000000000015"
    let coachingRequest = "00000000-0000-0000-0000-000000000016"
    let transcriptionKey = "00000000-0000-0000-0000-000000000017"
    let coachingKey = "00000000-0000-0000-0000-000000000018"
    let audioFile = "00000000-0000-0000-0000-000000000019"
}

private func insertConversation(
    _ db: Database,
    id: String,
    title: String,
    lifecycle: String,
    updatedAtMS: Int64
) throws {
    try db.execute(
        sql: "INSERT INTO conversations (id, title, lifecycle, title_authority, created_at_ms, updated_at_ms) VALUES (?, ?, ?, 'localFallback', 1, ?)",
        arguments: [id, title, lifecycle, updatedAtMS]
    )
}

private func insertDraft(
    _ db: Database,
    id: String,
    conversationID: String,
    text: String,
    updatedAtMS: Int64
) throws {
    try db.execute(
        sql: "INSERT INTO conversation_drafts VALUES (?, ?, 'text', ?, NULL, 'saved', 1, ?)",
        arguments: [id, conversationID, text, updatedAtMS]
    )
}

private func insertMessage(
    _ db: Database,
    id: String,
    conversationID: String,
    role: String,
    body: String,
    createdAtMS: Int64
) throws {
    try db.execute(
        sql: "INSERT INTO messages VALUES (?, ?, ?, ?, ?)",
        arguments: [id, conversationID, role, body, createdAtMS]
    )
}

private func insertVoiceTurn(_ db: Database, ids: IDs) throws {
    try db.execute(
        sql: """
            INSERT INTO voice_turns (
                id, conversation_id, transcription_request_id, transcription_idempotency_key,
                coaching_request_id, coaching_idempotency_key, state, stage, audio_file_id,
                audio_sha256, audio_duration_ms, accepted_transcript, uncertain_transcript,
                retry_count, next_retry_at_ms, failure_code, transcription_receipt,
                coaching_receipt, user_message_id, assistant_message_id, cleanup_state,
                created_at_ms, updated_at_ms
            ) VALUES (?, ?, ?, ?, ?, ?, 'paused', 'capture', ?, NULL, 1000, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, 'notRequired', 1, 1)
            """,
        arguments: [ids.voiceTurn, ids.newestDraftConversation, ids.transcriptionRequest, ids.transcriptionKey, ids.coachingRequest, ids.coachingKey, ids.audioFile]
    )
}
