import Foundation
import GRDB

public struct WeeklyWorkUndoToken: Codable, Sendable, Equatable {
    public let action: ActionRecord
    public init(action: ActionRecord) { self.action = action }
}

public struct WeeklyWorkRepository: Sendable {
    private let store: TaisaStore
    private let placements: WeeklyPlacementRepository
    private let events: WorkEventRepository
    private let actions: ActionRepository

    public init(store: TaisaStore) {
        self.store = store
        placements = WeeklyPlacementRepository(store: store)
        events = WorkEventRepository(store: store)
        actions = ActionRepository(store: store)
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
        let completed = ActionRecord(id: action.id, goalID: action.goalID, title: action.title, detail: action.detail, status: "completed", dueAtMS: action.dueAtMS, createdAtMS: action.createdAtMS, updatedAtMS: context.timestamp)
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
        let restored = ActionRecord(id: token.action.id, goalID: token.action.goalID, title: token.action.title, detail: token.action.detail, status: token.action.status, dueAtMS: token.action.dueAtMS, createdAtMS: token.action.createdAtMS, updatedAtMS: context.timestamp)
        try await actions.update(restored, context: context)
        try await events.create(
            WorkEventRecord(id: UUID().uuidString, actionID: restored.id, kind: .restored, fromWeekStartMS: nil, toWeekStartMS: nil, sourceType: "user", sourceID: nil, occurredAtMS: context.timestamp),
            context: MutationContext(id: UUID().uuidString, deviceID: context.deviceID, timestamp: context.timestamp)
        )
    }

    private func setPlacement(actionID: String, weekContaining: Date, plannedDay: Date?, timeZone: TimeZone, context: MutationContext) async throws {
        guard try await actions.get(id: actionID) != nil else { throw RepositoryError.notFound }
        let dates = try WeekCalendar(timeZone: timeZone).placement(weekContaining: weekContaining, plannedDay: plannedDay)
        let weekStartMS = Self.milliseconds(dates.weekStart)
        let plannedDayMS = dates.plannedDay.map(Self.milliseconds)
        let existing = try await activePlacement(actionID: actionID)
        if let existing, existing.weekStartMS == weekStartMS, existing.plannedDayMS == plannedDayMS { return }

        let kind: WorkEventKind = existing == nil ? .placed : .moved
        if let existing {
            if existing.weekStartMS == weekStartMS {
                try await placements.update(
                    WeeklyPlacementRecord(id: existing.id, actionID: existing.actionID, weekStartMS: weekStartMS, plannedDayMS: plannedDayMS, createdAtMS: existing.createdAtMS, updatedAtMS: context.timestamp),
                    context: context
                )
            } else {
                try await placements.delete(id: existing.id, context: context)
                try await placements.create(
                    WeeklyPlacementRecord(id: UUID().uuidString, actionID: actionID, weekStartMS: weekStartMS, plannedDayMS: plannedDayMS, createdAtMS: context.timestamp, updatedAtMS: context.timestamp),
                    context: MutationContext(id: UUID().uuidString, deviceID: context.deviceID, timestamp: context.timestamp)
                )
            }
        } else {
            try await placements.create(
                WeeklyPlacementRecord(id: UUID().uuidString, actionID: actionID, weekStartMS: weekStartMS, plannedDayMS: plannedDayMS, createdAtMS: context.timestamp, updatedAtMS: context.timestamp),
                context: context
            )
        }
        try await events.create(
            WorkEventRecord(id: UUID().uuidString, actionID: actionID, kind: kind, fromWeekStartMS: existing?.weekStartMS, toWeekStartMS: weekStartMS, sourceType: "user", sourceID: nil, occurredAtMS: context.timestamp),
            context: MutationContext(id: UUID().uuidString, deviceID: context.deviceID, timestamp: context.timestamp)
        )
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

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }
}
