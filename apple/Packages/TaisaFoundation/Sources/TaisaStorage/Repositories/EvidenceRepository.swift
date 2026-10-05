public struct EvidenceRepository: DomainRepository {
    private let core: RepositoryCore<EvidenceRecord>
    public init(store: TaisaStore) { core = RepositoryCore(store: store, spec: RepositorySpec(table: "evidence", entity: "evidence", fields: [("id", "id"), ("goalID", "goal_id"), ("actionID", "action_id"), ("title", "title"), ("detail", "detail"), ("occurredAtMS", "occurred_at_ms"), ("createdAtMS", "created_at_ms")], immutable: ["createdAtMS"], appendOnly: false)) }
    public func get(id: String) async throws -> EvidenceRecord? { try await core.get(id: id) }
    public func create(_ record: EvidenceRecord, context: MutationContext) async throws { try await core.create(record, context: context) }
    public func update(_ record: EvidenceRecord, context: MutationContext) async throws { try await core.update(record, context: context) }
    public func delete(id: String, context: MutationContext) async throws { try await core.delete(id: id, context: context) }
}
