public struct ActionRepository: DomainRepository {
    private let core: RepositoryCore<ActionRecord>
    public init(store: TaisaStore) { core = RepositoryCore(store: store, spec: RepositorySpec(table: "actions", entity: "action", fields: [("id", "id"), ("goalID", "goal_id"), ("milestoneID", "milestone_id"), ("title", "title"), ("detail", "detail"), ("status", "status"), ("dueDay", "due_day"), ("dueAtMS", "due_at_ms"), ("origin", "origin"), ("createdAtMS", "created_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["createdAtMS", "origin"], appendOnly: false)) }
    public func get(id: String) async throws -> ActionRecord? { try await core.get(id: id) }
    public func create(_ record: ActionRecord, context: MutationContext) async throws { try await core.create(record, context: context) }
    public func update(_ record: ActionRecord, context: MutationContext) async throws { try await core.update(record, context: context) }
    public func delete(id: String, context: MutationContext) async throws { try await core.delete(id: id, context: context) }
}
