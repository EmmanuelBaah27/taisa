import Foundation
import GRDB

enum WeeklyWorkTestError: Error { case injectedFailure }

public struct WeeklyWorkUndoToken: Codable, Sendable, Equatable {
    public let action: ActionRecord
    public init(action: ActionRecord) { self.action = action }
}

public struct WeeklyWorkRepository: Sendable {
    private let store: TaisaStore
    private let placements: WeeklyPlacementRepository
    private let events: WorkEventRepository
    private let actions: ActionRepository
    private let failAfterPlacementMutation: Bool

    public init(store: TaisaStore) {
        self.store = store
        placements = WeeklyPlacementRepository(store: store)
        events = WorkEventRepository(store: store)
        actions = ActionRepository(store: store)
        failAfterPlacementMutation = false
    }

    init(store: TaisaStore, failAfterPlacementMutation: Bool) {
        self.store = store
        placements = WeeklyPlacementRepository(store: store)
        events = WorkEventRepository(store: store)
        actions = ActionRepository(store: store)
        self.failAfterPlacementMutation = failAfterPlacementMutation
    }

    public func place(actionID: String, weekContaining: Date, plannedDay: Date?, timeZone: TimeZone, context: MutationContext) async throws {
        try await setPlacement(actionID: actionID, weekContaining: weekContaining, plannedDay: plannedDay, timeZone: timeZone, context: context)
    }

    public func move(actionID: String, weekContaining: Date, plannedDay: Date?, timeZone: TimeZone, context: MutationContext) async throws {
        try await setPlacement(actionID: actionID, weekContaining: weekContaining, plannedDay: plannedDay, timeZone: timeZone, context: context)
    }

    public func complete(actionID: String, context: MutationContext) async throws -> WeeklyWorkUndoToken {
        guard let action = try await actions.get(id: actionID) else { throw RepositoryError.notFound }
        if action.status == "completed" { return WeeklyWorkUndoToken(action: action) }
        let completed = ActionRecord(id: action.id, goalID: action.goalID, title: action.title, detail: action.detail, status: "completed", dueAtMS: action.dueAtMS, createdAtMS: action.createdAtMS, updatedAtMS: context.timestamp, milestoneID: action.milestoneID, dueDay: action.dueDay, origin: action.origin)
        try await actions.update(completed, context: context)
        try await events.create(
            WorkEventRecord(id: UUID().uuidString, actionID: action.id, kind: .completed, fromWeekStartMS: nil, toWeekStartMS: nil, sourceType: "user", sourceID: nil, occurredAtMS: context.timestamp),
            context: MutationContext(id: UUID().uuidString, deviceID: context.deviceID, timestamp: context.timestamp)
        )
        return WeeklyWorkUndoToken(action: action)
    }

    public func restore(_ token: WeeklyWorkUndoToken, context: MutationContext) async throws {
        guard let current = try await actions.get(id: token.action.id), current.status == "completed" else {
            throw RepositoryError.notFound
        }
        let restored = ActionRecord(id: token.action.id, goalID: token.action.goalID, title: token.action.title, detail: token.action.detail, status: token.action.status, dueAtMS: token.action.dueAtMS, createdAtMS: token.action.createdAtMS, updatedAtMS: context.timestamp, milestoneID: token.action.milestoneID, dueDay: token.action.dueDay, origin: token.action.origin)
        try await actions.update(restored, context: context)
        try await events.create(
            WorkEventRecord(id: UUID().uuidString, actionID: restored.id, kind: .restored, fromWeekStartMS: nil, toWeekStartMS: nil, sourceType: "user", sourceID: nil, occurredAtMS: context.timestamp),
            context: MutationContext(id: UUID().uuidString, deviceID: context.deviceID, timestamp: context.timestamp)
        )
    }

    private func setPlacement(actionID: String, weekContaining: Date, plannedDay: Date?, timeZone: TimeZone, context: MutationContext) async throws {
        let dates = try WeekCalendar(timeZone: timeZone).placement(weekContaining: weekContaining, plannedDay: plannedDay)
        let weekStartMS = Self.milliseconds(dates.weekStart)
        let plannedDayMS = dates.plannedDay.map(Self.milliseconds)
        try await store.write { db in
            guard try Int.fetchOne(db, sql: "SELECT count(*) FROM actions a WHERE a.id = ? COLLATE NOCASE AND a.status = 'active' AND NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'action' AND t.entity_id = a.id COLLATE NOCASE)", arguments: [actionID]) == 1 else { throw RepositoryError.notFound }
            let existing = try Self.activePlacement(actionID: actionID, db: db)
            if let existing, existing.weekStartMS == weekStartMS, existing.plannedDayMS == plannedDayMS { return }
            let kind: WorkEventKind = existing == nil ? .placed : .moved
            if let existing {
                if existing.weekStartMS == weekStartMS {
                    try Self.placementCore(store).update(WeeklyPlacementRecord(id: existing.id, actionID: existing.actionID, weekStartMS: weekStartMS, plannedDayMS: plannedDayMS, createdAtMS: existing.createdAtMS, updatedAtMS: context.timestamp), context: context, db: db)
                } else {
                    try Self.placementCore(store).delete(id: existing.id, context: context, db: db)
                    let replacement = WeeklyPlacementRecord(id: UUID().uuidString, actionID: actionID, weekStartMS: weekStartMS, plannedDayMS: plannedDayMS, createdAtMS: context.timestamp, updatedAtMS: context.timestamp)
                    try Self.placementCore(store).create(replacement, context: AssistantResponseRepository.childContext(context, entity: "weekly_placement", id: replacement.id), db: db)
                }
            } else if let inactive = try Self.inactivePlacement(actionID: actionID, weekStartMS: weekStartMS, db: db) {
                try db.execute(sql: "DELETE FROM weekly_placements WHERE id = ? COLLATE NOCASE", arguments: [inactive.id])
                let replacement = WeeklyPlacementRecord(id: UUID().uuidString, actionID: actionID, weekStartMS: weekStartMS, plannedDayMS: plannedDayMS, createdAtMS: context.timestamp, updatedAtMS: context.timestamp)
                try Self.placementCore(store).create(replacement, context: context, db: db)
            } else {
                let placement = WeeklyPlacementRecord(id: UUID().uuidString, actionID: actionID, weekStartMS: weekStartMS, plannedDayMS: plannedDayMS, createdAtMS: context.timestamp, updatedAtMS: context.timestamp)
                try Self.placementCore(store).create(placement, context: context, db: db)
            }
            if failAfterPlacementMutation { throw WeeklyWorkTestError.injectedFailure }
            let event = WorkEventRecord(id: UUID().uuidString, actionID: actionID, kind: kind, fromWeekStartMS: existing?.weekStartMS, toWeekStartMS: weekStartMS, sourceType: "user", sourceID: nil, occurredAtMS: context.timestamp)
            try Self.eventCore(store).create(event, context: AssistantResponseRepository.childContext(context, entity: "work_event", id: event.id), db: db)
        }
    }

    private func activePlacement(actionID: String) async throws -> WeeklyPlacementRecord? {
        try await store.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT p.* FROM weekly_placements p
                WHERE p.action_id = ? COLLATE NOCASE
                  AND NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'weekly_placement' AND t.entity_id = p.id COLLATE NOCASE)
                ORDER BY p.updated_at_ms DESC, p.id ASC LIMIT 1
                """, arguments: [actionID]) else { return nil }
            return WeeklyPlacementRecord(id: row["id"], actionID: row["action_id"], weekStartMS: row["week_start_ms"], plannedDayMS: row["planned_day_ms"], createdAtMS: row["created_at_ms"], updatedAtMS: row["updated_at_ms"])
        }
    }

    private static func inactivePlacement(actionID: String, weekStartMS: Int64, db: Database) throws -> WeeklyPlacementRecord? {
            guard let row = try Row.fetchOne(db, sql: """
                SELECT p.* FROM weekly_placements p
                WHERE p.action_id = ? COLLATE NOCASE AND p.week_start_ms = ?
                  AND EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'weekly_placement' AND t.entity_id = p.id COLLATE NOCASE)
                LIMIT 1
                """, arguments: [actionID, weekStartMS]) else { return nil }
            return WeeklyPlacementRecord(id: row["id"], actionID: row["action_id"], weekStartMS: row["week_start_ms"], plannedDayMS: row["planned_day_ms"], createdAtMS: row["created_at_ms"], updatedAtMS: row["updated_at_ms"])
    }

    private static func activePlacement(actionID: String, db: Database) throws -> WeeklyPlacementRecord? {
        guard let row = try Row.fetchOne(db, sql: "SELECT p.* FROM weekly_placements p WHERE p.action_id = ? COLLATE NOCASE AND NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'weekly_placement' AND t.entity_id = p.id COLLATE NOCASE) ORDER BY p.updated_at_ms DESC, p.id ASC LIMIT 1", arguments: [actionID]) else { return nil }
        return WeeklyPlacementRecord(id: row["id"], actionID: row["action_id"], weekStartMS: row["week_start_ms"], plannedDayMS: row["planned_day_ms"], createdAtMS: row["created_at_ms"], updatedAtMS: row["updated_at_ms"])
    }

    private static func placementCore(_ store: TaisaStore) -> RepositoryCore<WeeklyPlacementRecord> { .init(store: store, spec: .init(table: "weekly_placements", entity: "weekly_placement", fields: [("id", "id"), ("actionID", "action_id"), ("weekStartMS", "week_start_ms"), ("plannedDayMS", "planned_day_ms"), ("createdAtMS", "created_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["actionID", "createdAtMS"], appendOnly: false)) }
    private static func eventCore(_ store: TaisaStore) -> RepositoryCore<WorkEventRecord> { .init(store: store, spec: .init(table: "work_events", entity: "work_event", fields: [("id", "id"), ("actionID", "action_id"), ("kind", "kind"), ("fromWeekStartMS", "from_week_start_ms"), ("toWeekStartMS", "to_week_start_ms"), ("sourceType", "source_type"), ("sourceID", "source_id"), ("occurredAtMS", "occurred_at_ms")], immutable: [], appendOnly: true)) }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }
}
