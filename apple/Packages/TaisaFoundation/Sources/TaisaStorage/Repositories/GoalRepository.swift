public protocol MilestoneRepositoryContract: Sendable {
    func milestone(id: String) async throws -> MilestoneRecord?
    func createMilestone(_ record: MilestoneRecord, context: MutationContext) async throws
    func updateMilestone(_ record: MilestoneRecord, context: MutationContext) async throws
    func deleteMilestone(id: String, context: MutationContext) async throws
}

public struct GoalRepository: DomainRepository, MilestoneRepositoryContract {
    private let core: RepositoryCore<GoalRecord>
    public init(store: TaisaStore) { core = RepositoryCore(store: store, spec: RepositorySpec(table: "goals", entity: "goal", fields: [("id", "id"), ("title", "title"), ("detail", "detail"), ("status", "status"), ("createdAtMS", "created_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["createdAtMS"], appendOnly: false)) }
    public func get(id: String) async throws -> GoalRecord? { try await core.get(id: id) }
    public func create(_ record: GoalRecord, context: MutationContext) async throws { try await core.create(record, context: context) }
    public func update(_ record: GoalRecord, context: MutationContext) async throws { try await core.update(record, context: context) }
    public func delete(id: String, context: MutationContext) async throws { try await core.delete(id: id, context: context) }
    public func createMilestone(_ record: MilestoneRecord, context: MutationContext) async throws { try await milestoneCore.create(record, context: context) }
    public func updateMilestone(_ record: MilestoneRecord, context: MutationContext) async throws { try await milestoneCore.update(record, context: context) }
    public func milestone(id: String) async throws -> MilestoneRecord? { try await milestoneCore.get(id: id) }
    public func deleteMilestone(id: String, context: MutationContext) async throws { try await milestoneCore.delete(id: id, context: context) }
    private var milestoneCore: RepositoryCore<MilestoneRecord> { RepositoryCore(store: core.store, spec: RepositorySpec(table: "milestones", entity: "milestone", fields: [("id", "id"), ("goalID", "goal_id"), ("title", "title"), ("status", "status"), ("targetAtMS", "target_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["goalID"], appendOnly: false)) }
}
