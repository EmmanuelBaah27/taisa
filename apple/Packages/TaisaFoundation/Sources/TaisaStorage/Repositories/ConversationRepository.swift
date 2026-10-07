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
    public func delete(id: String, context: MutationContext) async throws { try await core.delete(id: id, context: context) }
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
