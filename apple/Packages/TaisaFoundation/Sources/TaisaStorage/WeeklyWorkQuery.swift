import Foundation
import GRDB

public struct WeeklyWorkItem: Sendable, Equatable {
    public let action: ActionRecord
    public let placement: WeeklyPlacementRecord
}

public struct WeeklyWorkSnapshot: Sendable, Equatable {
    public let items: [WeeklyWorkItem]
    public let unresolvedPriorWeekCount: Int
}

public struct WeeklyWorkQuery: Sendable {
    private let store: TaisaStore
    public init(store: TaisaStore) { self.store = store }

    public func snapshot(weekContaining date: Date, timeZone: TimeZone) async throws -> WeeklyWorkSnapshot {
        let week = try WeekCalendar(timeZone: timeZone).week(containing: date)
        let weekStartMS = Int64((week.start.timeIntervalSince1970 * 1_000).rounded())
        return try await store.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT a.*, p.id AS placement_id, p.action_id AS placement_action_id,
                       p.week_start_ms, p.planned_day_ms, p.created_at_ms AS placement_created_at_ms,
                       p.updated_at_ms AS placement_updated_at_ms
                FROM weekly_placements p
                JOIN actions a ON a.id = p.action_id
                WHERE p.week_start_ms = ? AND a.status = 'open'
                  AND NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'weekly_placement' AND t.entity_id = p.id COLLATE NOCASE)
                  AND NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'action' AND t.entity_id = a.id COLLATE NOCASE)
                ORDER BY p.planned_day_ms IS NULL, p.planned_day_ms, a.created_at_ms, a.id
                """, arguments: [weekStartMS])
            let items = rows.map { row in
                WeeklyWorkItem(
                    action: ActionRecord(id: row["id"], goalID: row["goal_id"], title: row["title"], detail: row["detail"], status: row["status"], dueAtMS: row["due_at_ms"], createdAtMS: row["created_at_ms"], updatedAtMS: row["updated_at_ms"]),
                    placement: WeeklyPlacementRecord(id: row["placement_id"], actionID: row["placement_action_id"], weekStartMS: row["week_start_ms"], plannedDayMS: row["planned_day_ms"], createdAtMS: row["placement_created_at_ms"], updatedAtMS: row["placement_updated_at_ms"])
                )
            }
            let unresolved = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM weekly_placements p
                JOIN actions a ON a.id = p.action_id
                WHERE p.week_start_ms < ? AND a.status = 'open'
                  AND NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'weekly_placement' AND t.entity_id = p.id COLLATE NOCASE)
                  AND NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'action' AND t.entity_id = a.id COLLATE NOCASE)
                """, arguments: [weekStartMS]) ?? 0
            return WeeklyWorkSnapshot(items: items, unresolvedPriorWeekCount: unresolved)
        }
    }
}
