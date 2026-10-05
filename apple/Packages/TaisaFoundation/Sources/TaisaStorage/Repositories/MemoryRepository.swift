public protocol MemorySourceRepositoryContract: Sendable {
    func source(id: String) async throws -> MemorySourceRecord?
    func createSource(_ record: MemorySourceRecord, context: MutationContext) async throws
    func updateSource(_ record: MemorySourceRecord, context: MutationContext) async throws
    func deleteSource(id: String, context: MutationContext) async throws
}

public struct MemoryRepository: DomainRepository, MemorySourceRepositoryContract {
    private let core: RepositoryCore<MemoryRecord>
    public init(store: TaisaStore) { core = RepositoryCore(store: store, spec: RepositorySpec(table: "memory_items", entity: "memory", fields: [("id", "id"), ("kind", "kind"), ("content", "content"), ("status", "status"), ("createdAtMS", "created_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["createdAtMS"], appendOnly: false)) }
    public func get(id: String) async throws -> MemoryRecord? { try await core.get(id: id) }
    public func create(_ record: MemoryRecord, context: MutationContext) async throws { try await core.create(record, context: context) }
    public func update(_ record: MemoryRecord, context: MutationContext) async throws { try await core.update(record, context: context) }
    public func delete(id: String, context: MutationContext) async throws { try await core.delete(id: id, context: context) }
    public func createSource(_ record: MemorySourceRecord, context: MutationContext) async throws { try await sourceCore.create(record, context: context) }
    public func updateSource(_ record: MemorySourceRecord, context: MutationContext) async throws { try await sourceCore.update(record, context: context) }
    public func source(id: String) async throws -> MemorySourceRecord? { try await sourceCore.get(id: id) }
    public func deleteSource(id: String, context: MutationContext) async throws { try await sourceCore.delete(id: id, context: context) }
    private var sourceCore: RepositoryCore<MemorySourceRecord> { RepositoryCore(store: core.store, spec: RepositorySpec(table: "memory_sources", entity: "memory_source", fields: [("id", "id"), ("memoryItemID", "memory_item_id"), ("sourceType", "source_type"), ("sourceID", "source_id"), ("createdAtMS", "created_at_ms")], immutable: ["createdAtMS"], appendOnly: false)) }
}
