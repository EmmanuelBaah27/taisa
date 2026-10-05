import Foundation
import GRDB

public struct PendingChange: Codable, Sendable, Equatable {
    public let id: String
    public let entityType: String
    public let entityID: String
    public let payload: Data
    public let createdAtMS: Int64
    public let attempts: Int
    public let retryCategory: String?
}

public struct ChangeJournal: Sendable {
    private let store: TaisaStore
    public init(store: TaisaStore) { self.store = store }

    public func pending(limit: Int) async throws -> [PendingChange] {
        guard limit > 0 else { return [] }
        return try await store.read { db in
            try Row.fetchAll(db, sql: "SELECT mutation_id, entity_type, entity_id, payload, created_at_ms, attempts, retry_category FROM outbox WHERE status IN ('pending', 'retrying') ORDER BY rowid LIMIT ?", arguments: [min(limit, 200)]).map { row in
                PendingChange(id: row["mutation_id"], entityType: row["entity_type"], entityID: row["entity_id"], payload: row["payload"], createdAtMS: row["created_at_ms"], attempts: row["attempts"], retryCategory: row["retry_category"])
            }
        }
    }

    public func acknowledge(id: String, at timestamp: Int64) async throws {
        guard timestamp >= 0 else { throw RepositoryError.invalidTimestamp }
        try await store.write { db in
            try db.execute(sql: "UPDATE outbox SET status = 'acknowledged', acknowledged_at_ms = MAX(created_at_ms, ?) WHERE mutation_id = ? AND status != 'acknowledged'", arguments: [timestamp, id])
        }
    }

    public func retry(id: String, category: String) async throws {
        guard ["offline", "quota", "rate_limited", "transport", "account"].contains(category) else { throw RepositoryError.invalidIdentifier }
        try await store.write { db in
            try db.execute(sql: "UPDATE outbox SET status = 'retrying', retry_category = ?, attempts = attempts + 1 WHERE mutation_id = ? AND status != 'acknowledged'", arguments: [category, id])
        }
    }

    // Coalescing is deliberately conservative. A newer mutation must name the
    // older version as a field ancestor before it may remove upload work.
    public func supersede(olderID: String, by newerID: String, at timestamp: Int64) async throws -> Bool {
        guard olderID != newerID, timestamp >= 0 else { return false }
        return try await store.write { db in
            guard let older = try Row.fetchOne(db, sql: "SELECT entity_type, entity_id, status, payload FROM outbox WHERE mutation_id = ?", arguments: [olderID]),
                  let newer = try Row.fetchOne(db, sql: "SELECT entity_type, entity_id, status, payload FROM outbox WHERE mutation_id = ?", arguments: [newerID]),
                  (older["entity_type"] as String) == (newer["entity_type"] as String),
                  (older["entity_id"] as String) == (newer["entity_id"] as String),
                  (older["status"] as String) == "pending", (newer["status"] as String) == "pending",
                  operation(in: older["payload"] as Data) == "update",
                  operation(in: newer["payload"] as Data) == "update" else { return false }
            let changed = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM field_versions WHERE entity_type = ? AND entity_id = ? AND version_id = ?", arguments: [older["entity_type"] as String, older["entity_id"] as String, olderID]) ?? 0
            let direct = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM field_versions WHERE entity_type = ? AND entity_id = ? AND parent_version_id = ? AND version_id = ?", arguments: [older["entity_type"] as String, older["entity_id"] as String, olderID, newerID]) ?? 0
            guard changed > 0, changed == direct else { return false }
            // Nil acknowledgement time distinguishes local coalescing from a
            // confirmed remote acknowledgement without changing the v1 schema.
            try db.execute(sql: "UPDATE outbox SET status = 'acknowledged', retry_category = 'superseded', acknowledged_at_ms = NULL WHERE mutation_id = ?", arguments: [olderID])
            return true
        }
    }

    private func operation(in payload: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return nil }
        return object["operation"] as? String
    }

    static func insert<Record: Encodable>(db: Database, context: MutationContext, entity: String, entityID: String, operation: String, record: Record?) throws {
        let payload = try canonicalPayload(context: context, entity: entity, entityID: entityID, operation: operation, record: record)
        try db.execute(sql: "INSERT INTO outbox (id, mutation_id, entity_type, entity_id, payload, status, created_at_ms) VALUES (?, ?, ?, ?, ?, 'pending', ?)", arguments: [UUID().uuidString, context.id, entity, entityID, payload, context.timestamp])
    }

    static func canonicalPayload<Record: Encodable>(context: MutationContext, entity: String, entityID: String, operation: String, record: Record?) throws -> Data {
        // sortedKeys yields stable bytes regardless of dictionary iteration order.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(CanonicalMutation(id: context.id, deviceID: context.deviceID, timestamp: context.timestamp, entityType: entity, entityID: entityID, operation: operation, record: record))
    }
}

private struct CanonicalMutation<Record: Encodable>: Encodable {
    let id: String
    let deviceID: String
    let timestamp: Int64
    let entityType: String
    let entityID: String
    let operation: String
    let record: Record?
}
