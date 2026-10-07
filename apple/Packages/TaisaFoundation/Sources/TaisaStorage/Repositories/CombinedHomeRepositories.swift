public struct WeeklyPlacementRepository: DomainRepository {
    private let core: RepositoryCore<WeeklyPlacementRecord>
    public init(store: TaisaStore) { core = RepositoryCore(store: store, spec: .init(table: "weekly_placements", entity: "weekly_placement", fields: [("id", "id"), ("actionID", "action_id"), ("weekStartMS", "week_start_ms"), ("plannedDayMS", "planned_day_ms"), ("createdAtMS", "created_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["actionID", "createdAtMS"], appendOnly: false)) }
    public func get(id: String) async throws -> WeeklyPlacementRecord? { try await core.get(id: id) }
    public func create(_ record: WeeklyPlacementRecord, context: MutationContext) async throws { try await core.create(record, context: context) }
    public func update(_ record: WeeklyPlacementRecord, context: MutationContext) async throws { try await core.update(record, context: context) }
    public func delete(id: String, context: MutationContext) async throws { try await core.delete(id: id, context: context) }
}

public struct WorkEventRepository: DomainRepository {
    private let core: RepositoryCore<WorkEventRecord>
    public init(store: TaisaStore) { core = RepositoryCore(store: store, spec: .init(table: "work_events", entity: "work_event", fields: [("id", "id"), ("actionID", "action_id"), ("kind", "kind"), ("fromWeekStartMS", "from_week_start_ms"), ("toWeekStartMS", "to_week_start_ms"), ("sourceType", "source_type"), ("sourceID", "source_id"), ("occurredAtMS", "occurred_at_ms")], immutable: [], appendOnly: true)) }
    public func get(id: String) async throws -> WorkEventRecord? { try await core.get(id: id) }
    public func create(_ record: WorkEventRecord, context: MutationContext) async throws { try await core.create(record, context: context) }
    public func update(_ record: WorkEventRecord, context: MutationContext) async throws { try await core.update(record, context: context) }
    public func delete(id: String, context: MutationContext) async throws { try await core.delete(id: id, context: context) }
}

public struct InsightRepository: DomainRepository {
    let core: RepositoryCore<InsightRecord>
    public init(store: TaisaStore) { core = RepositoryCore(store: store, spec: .init(table: "insights", entity: "insight", fields: [("id", "id"), ("body", "body"), ("status", "status"), ("isTimeSensitive", "is_time_sensitive"), ("homeEligibleUntilMS", "home_eligible_until_ms"), ("createdAtMS", "created_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["createdAtMS"], appendOnly: false)) }
    public func get(id: String) async throws -> InsightRecord? { try await core.get(id: id) }
    public func create(_ record: InsightRecord, context: MutationContext) async throws { try await core.create(record, context: context) }
    public func update(_ record: InsightRecord, context: MutationContext) async throws { try await core.update(record, context: context) }
    public func delete(id: String, context: MutationContext) async throws { try await core.delete(id: id, context: context) }
}

public struct InsightSourceRepository: DomainRepository {
    let core: RepositoryCore<InsightSourceRecord>
    public init(store: TaisaStore) { core = RepositoryCore(store: store, spec: .init(table: "insight_sources", entity: "insight_source", fields: [("id", "id"), ("insightID", "insight_id"), ("sourceType", "source_type"), ("sourceID", "source_id"), ("excerpt", "excerpt"), ("createdAtMS", "created_at_ms")], immutable: [], appendOnly: true)) }
    public func get(id: String) async throws -> InsightSourceRecord? { try await core.get(id: id) }
    public func create(_ record: InsightSourceRecord, context: MutationContext) async throws { try await core.create(record, context: context) }
    public func update(_ record: InsightSourceRecord, context: MutationContext) async throws { try await core.update(record, context: context) }
    public func delete(id: String, context: MutationContext) async throws { try await core.delete(id: id, context: context) }
}

public struct InsightRevisionRepository: DomainRepository {
    let core: RepositoryCore<InsightRevisionRecord>
    public init(store: TaisaStore) { core = RepositoryCore(store: store, spec: .init(table: "insight_revisions", entity: "insight_revision", fields: [("id", "id"), ("insightID", "insight_id"), ("proposedBody", "proposed_body"), ("status", "status"), ("sourceType", "source_type"), ("sourceID", "source_id"), ("createdAtMS", "created_at_ms"), ("resolvedAtMS", "resolved_at_ms")], immutable: ["proposedBody", "sourceType", "sourceID", "createdAtMS"], appendOnly: false)) }
    public func get(id: String) async throws -> InsightRevisionRecord? { try await core.get(id: id) }
    public func create(_ record: InsightRevisionRecord, context: MutationContext) async throws { try await core.create(record, context: context) }
    public func update(_ record: InsightRevisionRecord, context: MutationContext) async throws { try await core.update(record, context: context) }
    public func delete(id: String, context: MutationContext) async throws { try await core.delete(id: id, context: context) }
}
