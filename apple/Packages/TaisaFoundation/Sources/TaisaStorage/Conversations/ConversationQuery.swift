import GRDB

public protocol ConversationQuerying: Sendable {
    func loadIndex() async throws -> ConversationIndexSnapshot
    func loadConversation(id: String) async throws -> ConversationSnapshot
}

public struct ConversationQuery: ConversationQuerying, Sendable {
    private let store: TaisaStore

    public init(store: TaisaStore) {
        self.store = store
    }

    public func loadIndex() async throws -> ConversationIndexSnapshot {
        do {
            return try await store.read { db in
                let drafts = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT conversation_drafts.*
                    FROM conversation_drafts
                    JOIN conversations ON conversations.id = conversation_drafts.conversation_id
                    WHERE NOT EXISTS (
                        SELECT 1 FROM tombstones
                        WHERE entity_type = 'conversation'
                          AND entity_id = conversations.id COLLATE NOCASE
                    )
                    ORDER BY conversation_drafts.updated_at_ms DESC,
                             conversation_drafts.created_at_ms DESC,
                             conversation_drafts.id COLLATE NOCASE ASC
                    """
                ).map(Self.draft)
                let conversations = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT conversations.*
                    FROM conversations
                    WHERE lifecycle = 'completed'
                      AND NOT EXISTS (
                        SELECT 1 FROM tombstones
                        WHERE entity_type = 'conversation'
                          AND entity_id = conversations.id COLLATE NOCASE
                      )
                    ORDER BY updated_at_ms DESC, id COLLATE NOCASE ASC
                    """
                ).map(Self.conversation)
                return ConversationIndexSnapshot(drafts: drafts, conversations: conversations)
            }
        } catch let error as RepositoryError {
            throw error
        } catch {
            throw RepositoryError.persistenceFailed
        }
    }

    public func loadConversation(id sourceID: String) async throws -> ConversationSnapshot {
        guard let id = UUIDIdentity.canonical(sourceID) else { throw RepositoryError.invalidIdentifier }
        do {
            return try await store.read { db in
                guard let conversationRow = try Row.fetchOne(
                    db,
                    sql: """
                    SELECT * FROM conversations
                    WHERE id = ? COLLATE NOCASE
                      AND NOT EXISTS (
                        SELECT 1 FROM tombstones
                        WHERE entity_type = 'conversation' AND entity_id = ? COLLATE NOCASE
                      )
                    """,
                    arguments: [id, id]
                ) else { throw RepositoryError.notFound }
                let messageRows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT messages.* FROM messages
                    WHERE conversation_id = ? COLLATE NOCASE
                      AND NOT EXISTS (
                        SELECT 1 FROM tombstones
                        WHERE entity_type = 'message'
                          AND entity_id = messages.id COLLATE NOCASE
                      )
                    ORDER BY created_at_ms ASC, id COLLATE NOCASE ASC
                    """,
                    arguments: [id]
                )
                let revisionRows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT message_revisions.* FROM message_revisions
                    JOIN messages ON messages.id = message_revisions.message_id
                    WHERE messages.conversation_id = ? COLLATE NOCASE
                    ORDER BY message_revisions.created_at_ms ASC,
                             message_revisions.id COLLATE NOCASE ASC
                    """,
                    arguments: [id]
                )
                let draftRows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT * FROM conversation_drafts
                    WHERE conversation_id = ? COLLATE NOCASE
                    ORDER BY updated_at_ms DESC, id COLLATE NOCASE ASC
                    """,
                    arguments: [id]
                )
                return ConversationSnapshot(
                    conversation: Self.conversation(conversationRow),
                    visibleMessages: messageRows.map(Self.message),
                    revisions: revisionRows.map(Self.revision),
                    drafts: draftRows.map(Self.draft)
                )
            }
        } catch let error as RepositoryError {
            throw error
        } catch {
            throw RepositoryError.persistenceFailed
        }
    }

    private static func conversation(_ row: Row) -> ConversationRecord {
        ConversationRecord(
            id: row["id"], title: row["title"],
            lifecycle: ConversationLifecycle(rawValue: row["lifecycle"])!,
            titleAuthority: TitleAuthority(rawValue: row["title_authority"])!,
            createdAtMS: row["created_at_ms"], updatedAtMS: row["updated_at_ms"]
        )
    }

    private static func message(_ row: Row) -> MessageRecord {
        MessageRecord(
            id: row["id"], conversationID: row["conversation_id"], role: row["role"],
            body: row["body"], createdAtMS: row["created_at_ms"]
        )
    }

    private static func draft(_ row: Row) -> ConversationDraftRecord {
        ConversationDraftRecord(
            id: row["id"], conversationID: row["conversation_id"],
            inputMode: ConversationInputMode(rawValue: row["input_mode"])!,
            text: row["text"], voiceTurnID: row["voice_turn_id"],
            recoveryKind: DraftRecoveryKind(rawValue: row["recovery_kind"])!,
            createdAtMS: row["created_at_ms"], updatedAtMS: row["updated_at_ms"]
        )
    }

    private static func revision(_ row: Row) -> MessageRevisionRecord {
        MessageRevisionRecord(
            id: row["id"], messageID: row["message_id"], originalBody: row["original_body"],
            replacementMessageID: row["replacement_message_id"], createdAtMS: row["created_at_ms"]
        )
    }
}
