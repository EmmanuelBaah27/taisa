import Foundation
import GRDB

/// Message history is append-only: callers can create, read, and tombstone a
/// message, but cannot replace its body under the same stable ID.
public protocol MessageRepositoryContract: Sendable {
    func message(id: String) async throws -> MessageRecord?
    func createMessage(_ record: MessageRecord, context: MutationContext) async throws
    func deleteMessage(id: String, context: MutationContext) async throws
}

public struct ConversationRepository: DomainRepository, MessageRepositoryContract {
    private let core: RepositoryCore<ConversationRecord>
    public init(store: TaisaStore) { core = RepositoryCore(store: store, spec: RepositorySpec(table: "conversations", entity: "conversation", fields: [("id", "id"), ("title", "title"), ("lifecycle", "lifecycle"), ("titleAuthority", "title_authority"), ("createdAtMS", "created_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["createdAtMS"], appendOnly: false)) }
    public func get(id: String) async throws -> ConversationRecord? { try await core.get(id: id) }
    public func create(_ record: ConversationRecord, context: MutationContext) async throws { try await core.create(record, context: context) }
    public func update(_ record: ConversationRecord, context: MutationContext) async throws { try await core.update(record, context: context) }
    public func delete(id: String, context: MutationContext) async throws {
        guard let canonicalID = UUIDIdentity.canonical(id) else { throw RepositoryError.invalidIdentifier }
        try await core.delete(id: canonicalID, context: context) { db in
            let voiceTurnIDs = try String.fetchAll(
                db,
                sql: """
                SELECT voice_turn_id FROM conversation_drafts
                WHERE conversation_id = ? COLLATE NOCASE AND voice_turn_id IS NOT NULL
                """,
                arguments: [canonicalID]
            )
            for voiceTurnID in voiceTurnIDs {
                try Self.queueAudioCleanup(for: voiceTurnID, in: db)
            }
        }
    }
    public func createMessage(_ record: MessageRecord, context: MutationContext) async throws { try await messageCore.create(record, context: context) }
    public func message(id: String) async throws -> MessageRecord? { try await messageCore.get(id: id) }
    public func deleteMessage(id: String, context: MutationContext) async throws { try await messageCore.delete(id: id, context: context) }

    public func draft(id: String) async throws -> ConversationDraftRecord? {
        guard let id = UUIDIdentity.canonical(id) else { throw RepositoryError.invalidIdentifier }
        return try await core.store.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM conversation_drafts WHERE id = ? COLLATE NOCASE",
                arguments: [id]
            ).map(Self.decodeDraft)
        }
    }

    public func saveDraft(_ source: ConversationDraftRecord) async throws {
        let draft = try Self.validated(source)
        do {
            try await core.store.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO conversation_drafts (
                            id, conversation_id, input_mode, text, voice_turn_id,
                            recovery_kind, created_at_ms, updated_at_ms
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(id) DO UPDATE SET
                            conversation_id = excluded.conversation_id,
                            input_mode = excluded.input_mode,
                            text = excluded.text,
                            voice_turn_id = excluded.voice_turn_id,
                            recovery_kind = excluded.recovery_kind,
                            updated_at_ms = excluded.updated_at_ms
                        """,
                    arguments: [
                        draft.id, draft.conversationID, draft.inputMode.rawValue, draft.text,
                        draft.voiceTurnID, draft.recoveryKind.rawValue,
                        draft.createdAtMS, draft.updatedAtMS,
                    ]
                )
            }
        } catch let error as RepositoryError { throw error }
        catch { throw RepositoryError.persistenceFailed }
    }

    public func discardDraft(id sourceID: String) async throws {
        guard let id = UUIDIdentity.canonical(sourceID) else { throw RepositoryError.invalidIdentifier }
        do {
            try await core.store.write { db in
                guard let row = try Row.fetchOne(
                    db,
                    sql: "SELECT voice_turn_id FROM conversation_drafts WHERE id = ? COLLATE NOCASE",
                    arguments: [id]
                ) else { throw RepositoryError.notFound }
                let voiceTurnID: String? = row["voice_turn_id"]
                if let voiceTurnID {
                    try Self.queueAudioCleanup(for: voiceTurnID, in: db)
                }
                try db.execute(
                    sql: "DELETE FROM conversation_drafts WHERE id = ? COLLATE NOCASE",
                    arguments: [id]
                )
            }
        } catch let error as RepositoryError { throw error }
        catch { throw RepositoryError.persistenceFailed }
    }

    public func rename(id: String, title: String, context: MutationContext) async throws {
        guard let existing = try await get(id: id) else { throw RepositoryError.notFound }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw RepositoryError.persistenceFailed }
        try await update(
            ConversationRecord(
                id: existing.id, title: title, lifecycle: existing.lifecycle,
                titleAuthority: .user, createdAtMS: existing.createdAtMS,
                updatedAtMS: max(existing.createdAtMS, context.timestamp)
            ),
            context: context
        )
    }

    public func applyCorrection(_ source: ConversationCorrection, context: MutationContext) async throws {
        let correction = try Self.validated(source)
        guard UUIDIdentity.canonical(context.id) != nil,
              UUIDIdentity.canonical(context.deviceID) != nil else { throw RepositoryError.invalidIdentifier }
        guard context.timestamp >= 0 else { throw RepositoryError.invalidTimestamp }
        do {
            try await core.store.write { db in
                guard let userRow = try Row.fetchOne(
                    db,
                    sql: "SELECT conversation_id, role, body FROM messages WHERE id = ? COLLATE NOCASE",
                    arguments: [correction.originalUserMessageID]
                ), let assistantRow = try Row.fetchOne(
                    db,
                    sql: "SELECT conversation_id, role FROM messages WHERE id = ? COLLATE NOCASE",
                    arguments: [correction.originalAssistantMessageID]
                ) else { throw RepositoryError.notFound }
                let conversationID: String = userRow["conversation_id"]
                guard (userRow["role"] as String) == "user",
                      (assistantRow["role"] as String) == "assistant",
                      (assistantRow["conversation_id"] as String).caseInsensitiveCompare(conversationID) == .orderedSame,
                      correction.correctedUserMessage.conversationID.caseInsensitiveCompare(conversationID) == .orderedSame,
                      correction.regeneratedAssistantMessage.conversationID.caseInsensitiveCompare(conversationID) == .orderedSame else {
                    throw RepositoryError.persistenceFailed
                }
                try Self.insert(correction.correctedUserMessage, in: db)
                try Self.insert(correction.regeneratedAssistantMessage, in: db)
                try db.execute(
                    sql: "INSERT INTO message_revisions (id, message_id, original_body, replacement_message_id, created_at_ms) VALUES (?, ?, ?, ?, ?)",
                    arguments: [correction.revisionID, correction.originalUserMessageID, userRow["body"] as String, correction.correctedUserMessage.id, correction.createdAtMS]
                )
                for messageID in [correction.originalUserMessageID, correction.originalAssistantMessageID] {
                    try db.execute(
                        sql: "INSERT INTO tombstones (id, entity_type, entity_id, deletion_version_id, deleted_at_ms) VALUES (?, 'message', ?, ?, ?)",
                        arguments: [UUID().uuidString, messageID, UUID().uuidString, context.timestamp]
                    )
                }
                try db.execute(
                    sql: "UPDATE conversations SET updated_at_ms = MAX(updated_at_ms, ?) WHERE id = ? COLLATE NOCASE",
                    arguments: [context.timestamp, conversationID]
                )
            }
        } catch let error as RepositoryError { throw error }
        catch { throw RepositoryError.persistenceFailed }
    }

    public func revision(id: String) async throws -> MessageRevisionRecord? {
        guard let id = UUIDIdentity.canonical(id) else { throw RepositoryError.invalidIdentifier }
        return try await core.store.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM message_revisions WHERE id = ? COLLATE NOCASE",
                arguments: [id]
            ).map(Self.decodeRevision)
        }
    }

    public func saveRevision(_ source: MessageRevisionRecord) async throws {
        let replacementID = try Self.canonicalOptional(source.replacementMessageID)
        guard let id = UUIDIdentity.canonical(source.id),
              let messageID = UUIDIdentity.canonical(source.messageID),
              source.createdAtMS >= 0 else { throw RepositoryError.persistenceFailed }
        do {
            try await core.store.write { db in
                try db.execute(
                    sql: "INSERT INTO message_revisions (id, message_id, original_body, replacement_message_id, created_at_ms) VALUES (?, ?, ?, ?, ?)",
                    arguments: [id, messageID, source.originalBody, replacementID, source.createdAtMS]
                )
            }
        } catch let error as RepositoryError { throw error }
        catch { throw RepositoryError.persistenceFailed }
    }

    private var messageCore: RepositoryCore<MessageRecord> { RepositoryCore(store: core.store, spec: RepositorySpec(table: "messages", entity: "message", fields: [("id", "id"), ("conversationID", "conversation_id"), ("role", "role"), ("body", "body"), ("createdAtMS", "created_at_ms")], immutable: ["conversationID", "role", "body", "createdAtMS"], appendOnly: true)) }

    private static func validated(_ source: ConversationDraftRecord) throws -> ConversationDraftRecord {
        let voiceTurnID = try canonicalOptional(source.voiceTurnID)
        guard let id = UUIDIdentity.canonical(source.id),
              let conversationID = UUIDIdentity.canonical(source.conversationID),
              source.createdAtMS >= 0,
              source.updatedAtMS >= source.createdAtMS,
              (source.inputMode == .text && source.text != nil && voiceTurnID == nil)
                || (source.inputMode == .voice && source.text == nil && voiceTurnID != nil) else {
            throw RepositoryError.persistenceFailed
        }
        return ConversationDraftRecord(
            id: id, conversationID: conversationID, inputMode: source.inputMode,
            text: source.text, voiceTurnID: voiceTurnID, recoveryKind: source.recoveryKind,
            createdAtMS: source.createdAtMS, updatedAtMS: source.updatedAtMS
        )
    }

    private static func canonicalOptional(_ value: String?) throws -> String? {
        guard let value else { return nil }
        guard let canonical = UUIDIdentity.canonical(value) else { throw RepositoryError.invalidIdentifier }
        return canonical
    }

    private static func validated(_ source: ConversationCorrection) throws -> ConversationCorrection {
        guard let revisionID = UUIDIdentity.canonical(source.revisionID),
              let originalUserID = UUIDIdentity.canonical(source.originalUserMessageID),
              let originalAssistantID = UUIDIdentity.canonical(source.originalAssistantMessageID),
              let correctedID = UUIDIdentity.canonical(source.correctedUserMessage.id),
              let correctedConversationID = UUIDIdentity.canonical(source.correctedUserMessage.conversationID),
              let regeneratedID = UUIDIdentity.canonical(source.regeneratedAssistantMessage.id),
              let regeneratedConversationID = UUIDIdentity.canonical(source.regeneratedAssistantMessage.conversationID),
              source.correctedUserMessage.role == "user",
              source.regeneratedAssistantMessage.role == "assistant",
              source.createdAtMS >= 0,
              source.correctedUserMessage.createdAtMS >= 0,
              source.regeneratedAssistantMessage.createdAtMS >= source.correctedUserMessage.createdAtMS else {
            throw RepositoryError.persistenceFailed
        }
        return ConversationCorrection(
            revisionID: revisionID, originalUserMessageID: originalUserID,
            originalAssistantMessageID: originalAssistantID,
            correctedUserMessage: MessageRecord(
                id: correctedID, conversationID: correctedConversationID,
                role: source.correctedUserMessage.role, body: source.correctedUserMessage.body,
                createdAtMS: source.correctedUserMessage.createdAtMS
            ),
            regeneratedAssistantMessage: MessageRecord(
                id: regeneratedID, conversationID: regeneratedConversationID,
                role: source.regeneratedAssistantMessage.role, body: source.regeneratedAssistantMessage.body,
                createdAtMS: source.regeneratedAssistantMessage.createdAtMS
            ),
            createdAtMS: source.createdAtMS
        )
    }

    private static func insert(_ message: MessageRecord, in db: Database) throws {
        try db.execute(
            sql: "INSERT INTO messages (id, conversation_id, role, body, created_at_ms) VALUES (?, ?, ?, ?, ?)",
            arguments: [message.id, message.conversationID, message.role, message.body, message.createdAtMS]
        )
    }

    private static func queueAudioCleanup(for sourceID: String, in db: Database) throws {
        guard let id = UUIDIdentity.canonical(sourceID) else { throw RepositoryError.invalidIdentifier }
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT audio_file_id, updated_at_ms FROM voice_turns WHERE id = ? COLLATE NOCASE",
            arguments: [id]
        ) else { throw RepositoryError.notFound }
        let audioFileID: String? = row["audio_file_id"]
        if let audioFileID {
            try db.execute(
                sql: "INSERT INTO audio_cleanup_queue (turn_id, audio_file_id, completed_at_ms) VALUES (?, ?, NULL) ON CONFLICT(turn_id) DO UPDATE SET audio_file_id = excluded.audio_file_id, completed_at_ms = NULL",
                arguments: [id, audioFileID]
            )
        }
        try db.execute(
            sql: "UPDATE voice_turns SET state = 'discarded', stage = 'cleanup', cleanup_state = ?, updated_at_ms = MAX(updated_at_ms, ?) WHERE id = ? COLLATE NOCASE",
            arguments: [audioFileID == nil ? "notRequired" : "pending", row["updated_at_ms"] as Int64, id]
        )
    }

    private static func decodeDraft(_ row: Row) -> ConversationDraftRecord {
        ConversationDraftRecord(
            id: row["id"], conversationID: row["conversation_id"],
            inputMode: ConversationInputMode(rawValue: row["input_mode"])!,
            text: row["text"], voiceTurnID: row["voice_turn_id"],
            recoveryKind: DraftRecoveryKind(rawValue: row["recovery_kind"])!,
            createdAtMS: row["created_at_ms"], updatedAtMS: row["updated_at_ms"]
        )
    }

    private static func decodeRevision(_ row: Row) -> MessageRevisionRecord {
        MessageRevisionRecord(
            id: row["id"], messageID: row["message_id"],
            originalBody: row["original_body"], replacementMessageID: row["replacement_message_id"],
            createdAtMS: row["created_at_ms"]
        )
    }
}
