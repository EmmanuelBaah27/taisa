import GRDB

public struct HomeQuery: Sendable {
    private let store: TaisaStore

    public init(store: TaisaStore) {
        self.store = store
    }

    public func load(limits: HomeLimits = .default) async throws -> HomeSnapshot {
        guard limits.conversations > 0, limits.goals > 0, limits.actions > 0 else {
            throw HomeQueryError.invalidLimit
        }

        do {
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

                return HomeSnapshot(
                    conversations: conversationRows.map(Self.conversation),
                    goals: goalRows.map(Self.goal),
                    actions: actionRows.map(Self.action)
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
}
