public struct ProfileRepository: DomainRepository {
    private let core: RepositoryCore<ProfileRecord>
    public init(store: TaisaStore) { core = RepositoryCore(store: store, spec: RepositorySpec(table: "profile", entity: "profile", fields: [("id", "id"), ("displayName", "display_name"), ("headline", "headline"), ("biography", "biography"), ("updatedAtMS", "updated_at_ms")], immutable: [], appendOnly: false)) }
    public func get(id: String) async throws -> ProfileRecord? { try await core.get(id: id) }
    public func create(_ record: ProfileRecord, context: MutationContext) async throws { try await core.create(record, context: context) }
    public func update(_ record: ProfileRecord, context: MutationContext) async throws { try await core.update(record, context: context) }
    public func delete(id: String, context: MutationContext) async throws { try await core.delete(id: id, context: context) }
}
