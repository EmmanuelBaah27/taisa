import Foundation
import GRDB

public enum AssistantProposalDestination: Sendable {
    case goal(GoalRecord)
    case action(ActionRecord)
    case evidence(EvidenceRecord)
    case memoryCreate(MemoryRecord)
    case memoryUpdate(MemoryRecord)
    case memorySource(MemorySourceRecord)
    case insight(InsightRecord)
    case weekly(WeeklyPlacementRecord, WorkEventRecord, MutationContext)
}

public enum AssistantProposalAcceptanceError: Error, Sendable, Equatable {
    case staleTarget
    case alreadyResolved
    case injectedFailure
}

public struct AssistantProposalAcceptanceRepository: Sendable {
    private let store: TaisaStore
    private let failAfterDestination: Bool

    public init(store: TaisaStore) {
        self.store = store
        failAfterDestination = false
    }

    init(store: TaisaStore, failAfterDestination: Bool) {
        self.store = store
        self.failAfterDestination = failAfterDestination
    }

    public func accept(
        proposalID: String, payloadDigest: String,
        destination: AssistantProposalDestination, context: MutationContext,
        targetType: String, targetID: String, targetVersionID: String,
        decisionReceipt: String, resolvedAtMS: Int64
    ) async throws -> AssistantProposalRecord {
        do {
            return try await store.write { db in
                guard let row = try Row.fetchOne(
                    db, sql: "SELECT * FROM assistant_proposals WHERE id = ? COLLATE NOCASE",
                    arguments: [proposalID]
                ) else { throw RepositoryError.notFound }
                let current = AssistantResponseRepository.decodeProposal(row)
                if current.state == .accepted {
                    guard current.payloadDigest == payloadDigest,
                          current.targetType == targetType, current.targetID == targetID,
                          current.targetVersionID == targetVersionID,
                          current.decisionReceipt == decisionReceipt else {
                        throw AssistantProposalAcceptanceError.alreadyResolved
                    }
                    return current
                }
                guard current.state == .pending, current.payloadDigest == payloadDigest else {
                    throw AssistantProposalAcceptanceError.alreadyResolved
                }

                try apply(destination, context: context, db: db)
                if failAfterDestination { throw AssistantProposalAcceptanceError.injectedFailure }
                try db.execute(sql: """
                    UPDATE assistant_proposals SET state = 'accepted', target_type = ?, target_id = ?,
                        target_version_id = ?, decision_receipt = ?, resolved_at_ms = ?
                    WHERE id = ? COLLATE NOCASE AND state = 'pending'
                    """, arguments: [targetType, targetID, targetVersionID, decisionReceipt, resolvedAtMS, proposalID])
                guard db.changesCount == 1,
                      let updated = try Row.fetchOne(
                        db, sql: "SELECT * FROM assistant_proposals WHERE id = ? COLLATE NOCASE",
                        arguments: [proposalID]
                      ) else { throw RepositoryError.persistenceFailed }
                return AssistantResponseRepository.decodeProposal(updated)
            }
        } catch let error as AssistantProposalAcceptanceError { throw error }
        catch let error as RepositoryError { throw error }
        catch { throw RepositoryError.persistenceFailed }
    }

    private func apply(
        _ destination: AssistantProposalDestination, context: MutationContext, db: Database
    ) throws {
        switch destination {
        case .goal(let record):
            try core(GoalRecord.self, table: "goals", entity: "goal", fields: [("id", "id"), ("title", "title"), ("detail", "detail"), ("status", "status"), ("createdAtMS", "created_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["createdAtMS"]).create(record, context: context, db: db)
        case .action(let record):
            try core(ActionRecord.self, table: "actions", entity: "action", fields: [("id", "id"), ("goalID", "goal_id"), ("title", "title"), ("detail", "detail"), ("status", "status"), ("dueAtMS", "due_at_ms"), ("createdAtMS", "created_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["createdAtMS"]).create(record, context: context, db: db)
        case .evidence(let record):
            try core(EvidenceRecord.self, table: "evidence", entity: "evidence", fields: [("id", "id"), ("goalID", "goal_id"), ("actionID", "action_id"), ("title", "title"), ("detail", "detail"), ("occurredAtMS", "occurred_at_ms"), ("createdAtMS", "created_at_ms")], immutable: ["createdAtMS"]).create(record, context: context, db: db)
        case .memoryCreate(let record):
            try memoryCore().create(record, context: context, db: db)
        case .memoryUpdate(let record):
            try memoryCore().update(record, context: context, db: db)
        case .memorySource(let record):
            try core(MemorySourceRecord.self, table: "memory_sources", entity: "memory_source", fields: [("id", "id"), ("memoryItemID", "memory_item_id"), ("sourceType", "source_type"), ("sourceID", "source_id"), ("createdAtMS", "created_at_ms")], immutable: ["createdAtMS"]).create(record, context: context, db: db)
        case .insight(let record):
            try core(InsightRecord.self, table: "insights", entity: "insight", fields: [("id", "id"), ("body", "body"), ("status", "status"), ("isTimeSensitive", "is_time_sensitive"), ("homeEligibleUntilMS", "home_eligible_until_ms"), ("createdAtMS", "created_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["createdAtMS"]).create(record, context: context, db: db)
        case .weekly(let placement, let event, let eventContext):
            guard try Int.fetchOne(db, sql: "SELECT count(*) FROM actions WHERE id = ? COLLATE NOCASE", arguments: [placement.actionID]) == 1 else { throw AssistantProposalAcceptanceError.staleTarget }
            try core(WeeklyPlacementRecord.self, table: "weekly_placements", entity: "weekly_placement", fields: [("id", "id"), ("actionID", "action_id"), ("weekStartMS", "week_start_ms"), ("plannedDayMS", "planned_day_ms"), ("createdAtMS", "created_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["actionID", "createdAtMS"]).create(placement, context: context, db: db)
            try core(WorkEventRecord.self, table: "work_events", entity: "work_event", fields: [("id", "id"), ("actionID", "action_id"), ("kind", "kind"), ("fromWeekStartMS", "from_week_start_ms"), ("toWeekStartMS", "to_week_start_ms"), ("sourceType", "source_type"), ("sourceID", "source_id"), ("occurredAtMS", "occurred_at_ms")], immutable: [], appendOnly: true).create(event, context: eventContext, db: db)
        }
    }

    private func memoryCore() -> RepositoryCore<MemoryRecord> {
        core(MemoryRecord.self, table: "memory_items", entity: "memory", fields: [("id", "id"), ("kind", "kind"), ("content", "content"), ("status", "status"), ("createdAtMS", "created_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["createdAtMS"])
    }

    private func core<Record: DomainRecord>(
        _ type: Record.Type, table: String, entity: String,
        fields: [(String, String)], immutable: Set<String>, appendOnly: Bool = false
    ) -> RepositoryCore<Record> {
        RepositoryCore(store: store, spec: .init(table: table, entity: entity, fields: fields, immutable: immutable, appendOnly: appendOnly))
    }
}
