import Foundation
import GRDB

public struct InsightQuery: Sendable {
    private let store: TaisaStore
    public init(store: TaisaStore) { self.store = store }

    public func current() async throws -> [InsightRecord] { try await insights(status: "confirmed") }
    public func reviewNeeded() async throws -> [InsightRecord] { try await insights(status: "review_needed") }
    public func history() async throws -> [InsightRecord] {
        try await store.read { db in
            try Row.fetchAll(db, sql: baseInsightSQL + " AND i.status IN ('superseded', 'retired') ORDER BY i.updated_at_ms DESC, i.id").map(Self.insight)
        }
    }
    public func lead(atMS: Int64) async throws -> InsightRecord? {
        try await store.read { db in
            try Row.fetchOne(db, sql: baseInsightSQL + " AND i.status = 'confirmed' AND i.is_time_sensitive = 1 AND i.home_eligible_until_ms >= ? ORDER BY i.home_eligible_until_ms, i.updated_at_ms DESC, i.id LIMIT 1", arguments: [atMS]).map(Self.insight)
        }
    }
    public func sources(insightID: String) async throws -> [InsightSourceRecord] {
        try await store.read { db in
            try Row.fetchAll(db, sql: """
                SELECT s.* FROM insight_sources s
                WHERE s.insight_id = ? COLLATE NOCASE
                  AND NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'insight_source' AND t.entity_id = s.id COLLATE NOCASE)
                ORDER BY s.created_at_ms, s.id
                """, arguments: [insightID]).map {
                    InsightSourceRecord(id: $0["id"], insightID: $0["insight_id"], sourceType: $0["source_type"], sourceID: $0["source_id"], excerpt: $0["excerpt"], createdAtMS: $0["created_at_ms"])
                }
        }
    }
    public func revisions(insightID: String) async throws -> [InsightRevisionRecord] {
        try await store.read { db in
            try Row.fetchAll(db, sql: """
                SELECT r.* FROM insight_revisions r
                WHERE r.insight_id = ? COLLATE NOCASE
                  AND NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'insight_revision' AND t.entity_id = r.id COLLATE NOCASE)
                ORDER BY r.created_at_ms, r.id
                """, arguments: [insightID]).map(Self.revision)
        }
    }

    private func insights(status: String) async throws -> [InsightRecord] {
        try await store.read { db in
            try Row.fetchAll(db, sql: baseInsightSQL + " AND i.status = ? ORDER BY i.updated_at_ms DESC, i.id", arguments: [status]).map(Self.insight)
        }
    }
    private var baseInsightSQL: String { Self.baseInsightSQL }
    private static let baseInsightSQL = """
        SELECT i.* FROM insights i WHERE NOT EXISTS (
            SELECT 1 FROM tombstones t WHERE t.entity_type = 'insight' AND t.entity_id = i.id COLLATE NOCASE
        )
        """
    private static func insight(_ row: Row) -> InsightRecord {
        InsightRecord(id: row["id"], body: row["body"], status: InsightStatus(rawValue: row["status"])!, isTimeSensitive: (row["is_time_sensitive"] as Int64) == 1, homeEligibleUntilMS: row["home_eligible_until_ms"], createdAtMS: row["created_at_ms"], updatedAtMS: row["updated_at_ms"])
    }
    private static func revision(_ row: Row) -> InsightRevisionRecord {
        InsightRevisionRecord(id: row["id"], insightID: row["insight_id"], proposedBody: row["proposed_body"], status: InsightRevisionStatus(rawValue: row["status"])!, sourceType: row["source_type"], sourceID: row["source_id"], createdAtMS: row["created_at_ms"], resolvedAtMS: row["resolved_at_ms"])
    }
}
