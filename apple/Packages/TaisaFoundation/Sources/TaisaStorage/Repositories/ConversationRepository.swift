public struct ConversationRepository: DomainRepository {
    private let core: RepositoryCore<ConversationRecord>
    public init(store: TaisaStore) { core = RepositoryCore(store: store, spec: RepositorySpec(table: "conversations", entity: "conversation", fields: [("id", "id"), ("title", "title"), ("createdAtMS", "created_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["createdAtMS"], appendOnly: false)) }
    public func get(id: String) async throws -> ConversationRecord? { try await core.get(id: id) }
    public func create(_ record: ConversationRecord, context: MutationContext) async throws { try await core.create(record, context: context) }
    public func update(_ record: ConversationRecord, context: MutationContext) async throws { try await core.update(record, context: context) }
    public func delete(id: String, context: MutationContext) async throws { try await core.delete(id: id, context: context) }
    public func createMessage(_ record: MessageRecord, context: MutationContext) async throws { try await messageCore.create(record, context: context) }
    public func message(id: String) async throws -> MessageRecord? { try await messageCore.get(id: id) }
    public func deleteMessage(id: String, context: MutationContext) async throws { try await messageCore.delete(id: id, context: context) }
    private var messageCore: RepositoryCore<MessageRecord> { RepositoryCore(store: core.store, spec: RepositorySpec(table: "messages", entity: "message", fields: [("id", "id"), ("conversationID", "conversation_id"), ("role", "role"), ("body", "body"), ("createdAtMS", "created_at_ms")], immutable: ["conversationID", "role", "body", "createdAtMS"], appendOnly: true)) }
}
