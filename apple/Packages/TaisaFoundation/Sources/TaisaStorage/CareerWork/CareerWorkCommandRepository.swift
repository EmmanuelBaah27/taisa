import Foundation
import GRDB

public struct CareerWorkCommandRepository: Sendable {
    private let store: TaisaStore

    public init(store: TaisaStore) { self.store = store }

    public func createGoal(id: String = UUID().uuidString, title: String, detail: String, source: CareerWorkMutationSource = .user, sourceID: String? = nil, context: MutationContext) async throws -> GoalRecord {
        let title = try CareerWorkTitle.validating(title).value
        let record = GoalRecord(id: id, title: title, detail: detail, status: GoalStatus.active.rawValue, createdAtMS: context.timestamp, updatedAtMS: context.timestamp)
        try await store.write { db in
            try Self.goalCore(self.store).create(record, context: context, db: db)
            try Self.insertEvent(entity: "goal", id: record.id, transition: "created", from: nil, to: record.status, source: source, sourceID: sourceID, context: context, db: db)
        }
        return record
    }

    public func updateGoal(id: String, title: String, detail: String, context: MutationContext) async throws {
        let title = try CareerWorkTitle.validating(title).value
        try await store.write { db in
            guard let current = try Self.fetchGoal(id: id, db: db) else { throw RepositoryError.notFound }
            let updated = GoalRecord(id: current.id, title: title, detail: detail, status: current.status, createdAtMS: current.createdAtMS, updatedAtMS: context.timestamp)
            try Self.goalCore(self.store).update(updated, context: context, db: db)
        }
    }

    public func createMilestone(id: String = UUID().uuidString, goalID: String, title: String, targetAtMS: Int64?, source: CareerWorkMutationSource = .user, sourceID: String? = nil, context: MutationContext) async throws -> MilestoneRecord {
        let title = try CareerWorkTitle.validating(title).value
        let record = MilestoneRecord(id: id, goalID: goalID, title: title, status: MilestoneStatus.planned.storageValue, targetAtMS: targetAtMS, updatedAtMS: context.timestamp)
        try await store.write { db in
            try Self.milestoneCore(self.store).create(record, context: context, db: db)
            try Self.insertEvent(entity: "milestone", id: record.id, transition: "created", from: nil, to: record.status, source: source, sourceID: sourceID, context: context, db: db)
        }
        return record
    }

    public func createAction(id: String = UUID().uuidString, goalID: String?, title: String, detail: String, dueAtMS: Int64?, source: CareerWorkMutationSource = .user, sourceID: String? = nil, context: MutationContext) async throws -> ActionRecord {
        let title = try CareerWorkTitle.validating(title).value
        let record = ActionRecord(id: id, goalID: goalID, title: title, detail: detail, status: ActionStatus.open.rawValue, dueAtMS: dueAtMS, createdAtMS: context.timestamp, updatedAtMS: context.timestamp)
        try await store.write { db in
            try Self.actionCore(self.store).create(record, context: context, db: db)
            try Self.insertEvent(entity: "action", id: record.id, transition: "created", from: nil, to: record.status, source: source, sourceID: sourceID, context: context, db: db)
        }
        return record
    }

    public func addEvidence(goalID: String?, actionID: String?, title: String, detail: String, occurredAtMS: Int64, origin: EvidenceOrigin, originID: String?, context: MutationContext) async throws -> EvidenceRecord {
        guard goalID != nil || actionID != nil else { throw CareerWorkContractError.invalidRelationship }
        let title = try CareerWorkTitle.validating(title).value
        let record = EvidenceRecord(id: UUID().uuidString, goalID: goalID, actionID: actionID, title: title, detail: detail, occurredAtMS: occurredAtMS, createdAtMS: context.timestamp)
        try await store.write { db in
            try Self.evidenceCore(self.store).create(record, context: context, db: db)
            try db.execute(sql: "INSERT INTO evidence_provenance (evidence_id, origin_type, origin_id, supersedes_evidence_id, created_at_ms) VALUES (?, ?, ?, NULL, ?)", arguments: [record.id, origin.rawValue, originID, context.timestamp])
        }
        return record
    }

    public func correctEvidence(id: String, title: String, detail: String, occurredAtMS: Int64, origin: EvidenceOrigin, context: MutationContext) async throws -> EvidenceRecord {
        let title = try CareerWorkTitle.validating(title).value
        return try await store.write { db in
            guard let original = try Self.fetchEvidence(id: id, db: db) else { throw RepositoryError.notFound }
            let corrected = EvidenceRecord(id: UUID().uuidString, goalID: original.goalID, actionID: original.actionID, title: title, detail: detail, occurredAtMS: occurredAtMS, createdAtMS: context.timestamp)
            try Self.evidenceCore(self.store).create(corrected, context: context, db: db)
            try db.execute(sql: "INSERT INTO evidence_provenance (evidence_id, origin_type, origin_id, supersedes_evidence_id, created_at_ms) VALUES (?, ?, NULL, ?, ?)", arguments: [corrected.id, origin.rawValue, original.id, context.timestamp])
            return corrected
        }
    }

    public func transitionGoal(id: String, to next: GoalStatus, source: CareerWorkMutationSource, context: MutationContext) async throws -> GoalRecord {
        try await store.write { db in
            guard let current = try Self.fetchGoal(id: id, db: db), let status = GoalStatus(rawValue: current.status) else { throw RepositoryError.notFound }
            guard status.canTransition(to: next) else { throw CareerWorkContractError.invalidTransition }
            let updated = GoalRecord(id: current.id, title: current.title, detail: current.detail, status: next.rawValue, createdAtMS: current.createdAtMS, updatedAtMS: context.timestamp)
            try Self.goalCore(self.store).update(updated, context: context, db: db)
            let transition = next == .paused ? "paused" : (next == .completed ? "completed" : (status == .paused ? "resumed" : "reopened"))
            try Self.insertEvent(entity: "goal", id: id, transition: transition, from: status.rawValue, to: next.rawValue, source: source, context: context, db: db)
            return updated
        }
    }

    public func transitionMilestone(id: String, to next: MilestoneStatus, source: CareerWorkMutationSource, context: MutationContext) async throws -> MilestoneRecord {
        try await store.write { db in
            guard let current = try Self.fetchMilestone(id: id, db: db) else { throw RepositoryError.notFound }
            let status: MilestoneStatus = current.status == "open" ? .planned : .completed
            guard status.canTransition(to: next) else { throw CareerWorkContractError.invalidTransition }
            let updated = MilestoneRecord(id: current.id, goalID: current.goalID, title: current.title, status: next.storageValue, targetAtMS: current.targetAtMS, updatedAtMS: context.timestamp)
            try Self.milestoneCore(self.store).update(updated, context: context, db: db)
            try Self.insertEvent(entity: "milestone", id: id, transition: next == .completed ? "completed" : "reopened", from: current.status, to: updated.status, source: source, context: context, db: db)
            return updated
        }
    }

    public func transitionAction(id: String, to next: ActionStatus, source: CareerWorkMutationSource, context: MutationContext) async throws -> ActionRecord {
        try await store.write { db in
            guard let current = try Self.fetchAction(id: id, db: db), let status = ActionStatus(rawValue: current.status) else { throw RepositoryError.notFound }
            guard status.canTransition(to: next) else { throw CareerWorkContractError.invalidTransition }
            let updated = ActionRecord(id: current.id, goalID: current.goalID, title: current.title, detail: current.detail, status: next.rawValue, dueAtMS: current.dueAtMS, createdAtMS: current.createdAtMS, updatedAtMS: context.timestamp)
            try Self.actionCore(self.store).update(updated, context: context, db: db)
            try Self.insertEvent(entity: "action", id: id, transition: next == .completed ? "completed" : "reopened", from: status.rawValue, to: next.rawValue, source: source, context: context, db: db)
            return updated
        }
    }

    public func archiveGoal(id: String, context: MutationContext) async throws {
        try await store.write { db in
            guard let goal = try Self.fetchGoal(id: id, db: db) else { throw RepositoryError.notFound }
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM career_work_archives WHERE entity_type = 'goal' AND entity_id = ? AND restored_at_ms IS NULL", arguments: [id]) == 0 else { throw CareerWorkContractError.invalidTransition }
            try db.execute(sql: "INSERT INTO career_work_archives (id, entity_type, entity_id, archived_at_ms) VALUES (?, 'goal', ?, ?)", arguments: [UUID().uuidString, id, context.timestamp])
            try Self.insertEvent(entity: "goal", id: id, transition: "archived", from: goal.status, to: goal.status, source: .user, context: context, db: db)
        }
    }

    public func restoreGoal(id: String, context: MutationContext) async throws {
        try await store.write { db in
            guard let goal = try Self.fetchGoal(id: id, db: db) else { throw RepositoryError.notFound }
            guard let archiveID = try String.fetchOne(db, sql: "SELECT id FROM career_work_archives WHERE entity_type = 'goal' AND entity_id = ? AND restored_at_ms IS NULL", arguments: [id]) else { throw CareerWorkContractError.invalidTransition }
            try db.execute(sql: "UPDATE career_work_archives SET restored_at_ms = ? WHERE id = ?", arguments: [context.timestamp, archiveID])
            try Self.insertEvent(entity: "goal", id: id, transition: "restored", from: goal.status, to: goal.status, source: .user, context: context, db: db)
        }
    }

    private static func insertEvent(entity: String, id: String, transition: String, from: String?, to: String, source: CareerWorkMutationSource, sourceID: String? = nil, context: MutationContext, db: Database) throws {
        try db.execute(sql: "INSERT INTO career_work_events (id, entity_type, entity_id, transition, from_status, to_status, source_type, source_id, occurred_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", arguments: [UUID().uuidString, entity, id, transition, from, to, source.rawValue, sourceID, context.timestamp])
    }

    private static func fetchGoal(id: String, db: Database) throws -> GoalRecord? { try Row.fetchOne(db, sql: "SELECT * FROM goals WHERE id = ? COLLATE NOCASE", arguments: [id]).map { GoalRecord(id: $0["id"], title: $0["title"], detail: $0["detail"], status: $0["status"], createdAtMS: $0["created_at_ms"], updatedAtMS: $0["updated_at_ms"]) } }
    private static func fetchMilestone(id: String, db: Database) throws -> MilestoneRecord? { try Row.fetchOne(db, sql: "SELECT * FROM milestones WHERE id = ? COLLATE NOCASE", arguments: [id]).map { MilestoneRecord(id: $0["id"], goalID: $0["goal_id"], title: $0["title"], status: $0["status"], targetAtMS: $0["target_at_ms"], updatedAtMS: $0["updated_at_ms"]) } }
    private static func fetchAction(id: String, db: Database) throws -> ActionRecord? { try Row.fetchOne(db, sql: "SELECT * FROM actions WHERE id = ? COLLATE NOCASE", arguments: [id]).map { ActionRecord(id: $0["id"], goalID: $0["goal_id"], title: $0["title"], detail: $0["detail"], status: $0["status"], dueAtMS: $0["due_at_ms"], createdAtMS: $0["created_at_ms"], updatedAtMS: $0["updated_at_ms"]) } }
    private static func fetchEvidence(id: String, db: Database) throws -> EvidenceRecord? { try Row.fetchOne(db, sql: "SELECT * FROM evidence WHERE id = ? COLLATE NOCASE", arguments: [id]).map { EvidenceRecord(id: $0["id"], goalID: $0["goal_id"], actionID: $0["action_id"], title: $0["title"], detail: $0["detail"], occurredAtMS: $0["occurred_at_ms"], createdAtMS: $0["created_at_ms"]) } }

    private static func goalCore(_ store: TaisaStore) -> RepositoryCore<GoalRecord> { .init(store: store, spec: .init(table: "goals", entity: "goal", fields: [("id", "id"), ("title", "title"), ("detail", "detail"), ("status", "status"), ("createdAtMS", "created_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["createdAtMS"], appendOnly: false)) }
    private static func milestoneCore(_ store: TaisaStore) -> RepositoryCore<MilestoneRecord> { .init(store: store, spec: .init(table: "milestones", entity: "milestone", fields: [("id", "id"), ("goalID", "goal_id"), ("title", "title"), ("status", "status"), ("targetAtMS", "target_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["goalID"], appendOnly: false)) }
    private static func actionCore(_ store: TaisaStore) -> RepositoryCore<ActionRecord> { .init(store: store, spec: .init(table: "actions", entity: "action", fields: [("id", "id"), ("goalID", "goal_id"), ("title", "title"), ("detail", "detail"), ("status", "status"), ("dueAtMS", "due_at_ms"), ("createdAtMS", "created_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["createdAtMS"], appendOnly: false)) }
    private static func evidenceCore(_ store: TaisaStore) -> RepositoryCore<EvidenceRecord> { .init(store: store, spec: .init(table: "evidence", entity: "evidence", fields: [("id", "id"), ("goalID", "goal_id"), ("actionID", "action_id"), ("title", "title"), ("detail", "detail"), ("occurredAtMS", "occurred_at_ms"), ("createdAtMS", "created_at_ms")], immutable: ["createdAtMS"], appendOnly: false)) }
}
