import Foundation
import GRDB

public struct HomeQuery: Sendable {
    private let store: TaisaStore

    public init(store: TaisaStore) {
        self.store = store
    }

    public func load(limits: HomeLimits = .default, weekContaining date: Date = Date(), timeZone: TimeZone = .current) async throws -> HomeSnapshot {
        guard limits.conversations > 0, limits.goals > 0, limits.actions > 0 else {
            throw HomeQueryError.invalidLimit
        }

        do {
            let week = try WeekCalendar(timeZone: timeZone).week(containing: date)
            let weekStartMS = Int64((week.start.timeIntervalSince1970 * 1_000).rounded())
            let nowMS = Int64((date.timeIntervalSince1970 * 1_000).rounded())
            return try await store.read { db in
                let conversationRows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT id, title, created_at_ms, updated_at_ms
                    FROM conversations
                    WHERE NOT EXISTS (
                        SELECT 1 FROM tombstones
                        WHERE entity_type = 'conversation' AND entity_id = conversations.id
                    )
                    ORDER BY updated_at_ms DESC, id ASC
                    LIMIT ?
                    """,
                    arguments: [limits.conversations]
                )
                let goalRows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT id, title, detail, status, created_at_ms, updated_at_ms
                    FROM goals
                    WHERE status = 'active'
                      AND NOT EXISTS (
                        SELECT 1 FROM tombstones
                        WHERE entity_type = 'goal' AND entity_id = goals.id
                      )
                    ORDER BY updated_at_ms DESC, id ASC
                    LIMIT ?
                    """,
                    arguments: [limits.goals]
                )
                let actionRows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT id, goal_id, title, detail, status, due_at_ms, created_at_ms, updated_at_ms
                    FROM actions
                    WHERE status = 'open'
                      AND NOT EXISTS (
                        SELECT 1 FROM tombstones
                        WHERE entity_type = 'action' AND entity_id = actions.id
                      )
                    ORDER BY due_at_ms IS NULL ASC, due_at_ms ASC, updated_at_ms DESC, id ASC
                    LIMIT ?
                    """,
                    arguments: [limits.actions]
                )
                let weeklyRows = try Row.fetchAll(db, sql: """
                    SELECT a.*, p.id AS placement_id, p.action_id AS placement_action_id,
                           p.week_start_ms, p.planned_day_ms, p.created_at_ms AS placement_created_at_ms,
                           p.updated_at_ms AS placement_updated_at_ms
                    FROM weekly_placements p JOIN actions a ON a.id = p.action_id
                    WHERE p.week_start_ms = ? AND a.status = 'open'
                      AND NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'weekly_placement' AND t.entity_id = p.id COLLATE NOCASE)
                      AND NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'action' AND t.entity_id = a.id COLLATE NOCASE)
                    ORDER BY p.planned_day_ms IS NULL, p.planned_day_ms, a.created_at_ms, a.id
                    """, arguments: [weekStartMS])
                let unresolved = try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM weekly_placements p JOIN actions a ON a.id = p.action_id
                    WHERE p.week_start_ms < ? AND a.status = 'open'
                      AND NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'weekly_placement' AND t.entity_id = p.id COLLATE NOCASE)
                      AND NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'action' AND t.entity_id = a.id COLLATE NOCASE)
                    """, arguments: [weekStartMS]) ?? 0
                let grounded = "EXISTS (SELECT 1 FROM insight_sources s WHERE s.insight_id = i.id COLLATE NOCASE AND NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'insight_source' AND t.entity_id = s.id COLLATE NOCASE))"
                let leadRow = try Row.fetchOne(db, sql: """
                    SELECT i.* FROM insights i
                    WHERE i.status = 'confirmed' AND i.is_time_sensitive = 1 AND i.home_eligible_until_ms >= ?
                      AND \(grounded)
                      AND NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'insight' AND t.entity_id = i.id COLLATE NOCASE)
                    ORDER BY i.home_eligible_until_ms, i.updated_at_ms DESC, i.id LIMIT 1
                    """, arguments: [nowMS])
                let hasInsightHistory = try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM insights i
                    WHERE \(grounded)
                      AND NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'insight' AND t.entity_id = i.id COLLATE NOCASE)
                    """) ?? 0 > 0

                return HomeSnapshot(
                    conversations: conversationRows.map(Self.conversation),
                    goals: goalRows.map(Self.goal),
                    actions: actionRows.map(Self.action),
                    thisWeek: weeklyRows.map(Self.weeklyItem),
                    unresolvedPriorWeekCount: unresolved,
                    leadInsight: leadRow.map(Self.insight),
                    hasConfirmedInsightHistory: hasInsightHistory
                )
            }
        } catch let error as HomeQueryError {
            throw error
        } catch {
            throw HomeQueryError.readFailed
        }
    }

    private static func conversation(_ row: Row) -> ConversationRecord {
        ConversationRecord(
            id: row["id"],
            title: row["title"],
            createdAtMS: row["created_at_ms"],
            updatedAtMS: row["updated_at_ms"]
        )
    }

    private static func goal(_ row: Row) -> GoalRecord {
        GoalRecord(
            id: row["id"],
            title: row["title"],
            detail: row["detail"],
            status: row["status"],
            createdAtMS: row["created_at_ms"],
            updatedAtMS: row["updated_at_ms"]
        )
    }

    private static func action(_ row: Row) -> ActionRecord {
        ActionRecord(
            id: row["id"],
            goalID: row["goal_id"],
            title: row["title"],
            detail: row["detail"],
            status: row["status"],
            dueAtMS: row["due_at_ms"],
            createdAtMS: row["created_at_ms"],
            updatedAtMS: row["updated_at_ms"]
        )
    }

    private static func weeklyItem(_ row: Row) -> WeeklyWorkItem {
        WeeklyWorkItem(
            action: action(row),
            placement: WeeklyPlacementRecord(id: row["placement_id"], actionID: row["placement_action_id"], weekStartMS: row["week_start_ms"], plannedDayMS: row["planned_day_ms"], createdAtMS: row["placement_created_at_ms"], updatedAtMS: row["placement_updated_at_ms"])
        )
    }

    private static func insight(_ row: Row) -> InsightRecord {
        InsightRecord(id: row["id"], body: row["body"], status: InsightStatus(rawValue: row["status"])!, isTimeSensitive: (row["is_time_sensitive"] as Int64) == 1, homeEligibleUntilMS: row["home_eligible_until_ms"], createdAtMS: row["created_at_ms"], updatedAtMS: row["updated_at_ms"])
    }
}
