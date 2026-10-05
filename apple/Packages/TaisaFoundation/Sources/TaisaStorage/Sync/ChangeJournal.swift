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
    public let causality: CausalSnapshot
}

public struct ChangeJournal: Sendable {
    private let store: TaisaStore
    public init(store: TaisaStore) { self.store = store }

    /// Observation only. An uploader must call reservePending before sending;
    /// that atomic transition prevents an unsent edit from being coalesced.
    public func pending(limit: Int) async throws -> [PendingChange] {
        guard limit > 0 else { return [] }
        return try await safeRead { db in
            try Row.fetchAll(db, sql: "SELECT mutation_id, entity_type, entity_id, payload, created_at_ms, attempts, retry_category FROM outbox WHERE status = 'pending' OR (status = 'retrying' AND COALESCE(retry_category, '') NOT LIKE 'reserved:%') ORDER BY rowid LIMIT ?", arguments: [min(limit, 200)]).map(Self.pendingChange)
        }
    }

    /// Atomically claims at most 200 changes. An expired lease may be claimed
    /// again after a crash; the same opaque mutation ID makes replay safe.
    public func reservePending(limit: Int, at timestamp: Int64, leaseDurationMS: Int64) async throws -> [ReservedChange] {
        guard timestamp >= 0, leaseDurationMS > 0 else { throw RepositoryError.invalidTimestamp }
        let (expiry, overflow) = timestamp.addingReportingOverflow(leaseDurationMS)
        guard !overflow else { throw RepositoryError.invalidTimestamp }
        guard limit > 0 else { return [] }
        let reservationID = UUID().uuidString
        let marker = Self.reservationMarker(id: reservationID, expiresAtMS: expiry)
        return try await safeWrite { db in
            let rows = try Row.fetchAll(db, sql: "SELECT mutation_id, entity_type, entity_id, payload, created_at_ms, attempts, retry_category FROM outbox WHERE status = 'pending' OR (status = 'retrying' AND (COALESCE(retry_category, '') NOT LIKE 'reserved:%' OR CAST(substr(retry_category, 10, 20) AS INTEGER) <= ?)) ORDER BY rowid LIMIT ?", arguments: [timestamp, min(limit, 200)])
            return try rows.map { row in
                let change = try Self.pendingChange(row)
                try db.execute(sql: "UPDATE outbox SET status = 'retrying', retry_category = ? WHERE mutation_id = ?", arguments: [marker, change.id])
                return ReservedChange(change: change, reservationID: reservationID, expiresAtMS: expiry)
            }
        }
    }

    public func acknowledge(id: String, at timestamp: Int64) async throws {
        guard timestamp >= 0 else { throw RepositoryError.invalidTimestamp }
        try await safeWrite { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT status, retry_category, attempts, acknowledged_at_ms FROM outbox WHERE mutation_id = ?", arguments: [id]) else { return }
            let current = try Self.state(row)
            let prior: Int64? = row["acknowledged_at_ms"]
            let acknowledgedAt = max(timestamp, prior ?? timestamp)
            switch current {
            case .superseded:
                // A stale uploader can still report a real remote success.
                try db.execute(sql: "UPDATE outbox SET acknowledged_at_ms = MAX(created_at_ms, ?) WHERE mutation_id = ?", arguments: [acknowledgedAt, id])
            case .remotelyAcknowledged:
                return
            default:
                try db.execute(sql: "UPDATE outbox SET status = 'acknowledged', retry_category = NULL, acknowledged_at_ms = MAX(created_at_ms, ?) WHERE mutation_id = ?", arguments: [acknowledgedAt, id])
            }
        }
    }

    public func retry(id: String, category: String, reservationID: String? = nil) async throws {
        guard ["offline", "quota", "rate_limited", "transport", "account"].contains(category) else { throw RepositoryError.invalidIdentifier }
        try await safeWrite { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT status, retry_category, attempts, acknowledged_at_ms FROM outbox WHERE mutation_id = ?", arguments: [id]) else { return }
            switch try Self.state(row) {
            case .reserved(let token, _, _):
                guard token == reservationID else { throw RepositoryError.reservationMismatch }
            case .pending, .retrying:
                guard reservationID == nil else { throw RepositoryError.reservationMismatch }
            case .superseded, .remotelyAcknowledged:
                return
            }
            try db.execute(sql: "UPDATE outbox SET status = 'retrying', retry_category = ?, attempts = attempts + 1 WHERE mutation_id = ?", arguments: [category, id])
        }
    }

    public func state(id: String) async throws -> JournalState? {
        try await safeRead { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT status, retry_category, attempts, acknowledged_at_ms FROM outbox WHERE mutation_id = ?", arguments: [id]) else { return nil }
            return try Self.state(row)
        }
    }

    /// Follows durable replacement links. Only a transport acknowledgement of
    /// this mutation or its surviving descendant confirms remote coverage.
    public func remoteCoverage(id: String) async throws -> JournalCoverage {
        try await safeRead { db in
            var current = id
            var visited: Set<String> = []
            while visited.insert(current).inserted, visited.count <= 10_000 {
                guard let row = try Row.fetchOne(db, sql: "SELECT status, retry_category, attempts, acknowledged_at_ms FROM outbox WHERE mutation_id = ?", arguments: [current]) else { return .unverifiable }
                switch try Self.state(row) {
                case .remotelyAcknowledged: return .confirmed
                case .superseded(let replacement, let acknowledgement):
                    if acknowledgement != nil { return .confirmed }
                    current = replacement
                case .pending, .retrying, .reserved: return .waitingFor(current)
                }
            }
            return .unverifiable
        }
    }

    // Coalescing is deliberately conservative. A newer mutation must name the
    // older version as a field ancestor before it may remove upload work.
    public func supersede(olderID: String, by newerID: String, at timestamp: Int64) async throws -> Bool {
        guard olderID != newerID, timestamp >= 0 else { return false }
        return try await safeWrite { db in
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
            // The replacement link and nil timestamp distinguish local
            // coalescing from a confirmed remote acknowledgement in v1.
            try db.execute(sql: "UPDATE outbox SET status = 'acknowledged', retry_category = ?, acknowledged_at_ms = NULL WHERE mutation_id = ?", arguments: ["superseded:\(newerID)", olderID])
            return true
        }
    }

    private func safeRead<Value: Sendable>(_ body: @Sendable (Database) throws -> Value) async throws -> Value {
        do { return try await store.read(body) }
        catch let error as RepositoryError { throw error }
        catch { throw RepositoryError.persistenceFailed }
    }

    private func safeWrite<Value: Sendable>(_ body: @Sendable (Database) throws -> Value) async throws -> Value {
        do { return try await store.write(body) }
        catch let error as RepositoryError { throw error }
        catch { throw RepositoryError.persistenceFailed }
    }

    private func operation(in payload: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return nil }
        return object["operation"] as? String
    }

    private static func pendingChange(_ row: Row) throws -> PendingChange {
        let payload: Data = row["payload"]
        return PendingChange(id: row["mutation_id"], entityType: row["entity_type"], entityID: row["entity_id"], payload: payload, createdAtMS: row["created_at_ms"], attempts: row["attempts"], retryCategory: row["retry_category"], causality: try causality(from: payload))
    }

    private static func reservationMarker(id: String, expiresAtMS: Int64) -> String {
        let digits = String(expiresAtMS)
        return "reserved:" + String(repeating: "0", count: max(0, 20 - digits.count)) + digits + ":" + id
    }

    private static func state(_ row: Row) throws -> JournalState {
        let status: String = row["status"]
        let category: String? = row["retry_category"]
        let attempts: Int = row["attempts"]
        let acknowledgedAt: Int64? = row["acknowledged_at_ms"]
        switch status {
        case "pending":
            guard category == nil, acknowledgedAt == nil else { throw RepositoryError.persistenceFailed }
            return .pending
        case "retrying":
            guard acknowledgedAt == nil, let category else { throw RepositoryError.persistenceFailed }
            if category.hasPrefix("reserved:") {
                let parts = category.split(separator: ":", omittingEmptySubsequences: false)
                guard parts.count == 3, parts[1].count == 20,
                      let expiry = Int64(parts[1]), UUID(uuidString: String(parts[2])) != nil else { throw RepositoryError.persistenceFailed }
                return .reserved(reservationID: String(parts[2]), expiresAtMS: expiry, attempts: attempts)
            }
            guard ["offline", "quota", "rate_limited", "transport", "account"].contains(category) else { throw RepositoryError.persistenceFailed }
            return .retrying(category: category, attempts: attempts)
        case "acknowledged":
            if let category, category.hasPrefix("superseded:") {
                let replacement = String(category.dropFirst("superseded:".count))
                guard UUID(uuidString: replacement) != nil else { throw RepositoryError.persistenceFailed }
                return .superseded(by: replacement, remotelyAcknowledgedAtMS: acknowledgedAt)
            }
            guard category == nil, let acknowledgedAt else { throw RepositoryError.persistenceFailed }
            return .remotelyAcknowledged(atMS: acknowledgedAt)
        default:
            throw RepositoryError.persistenceFailed
        }
    }

    static func insert<Record: Encodable>(db: Database, context: MutationContext, entity: String, entityID: String, operation: String, record: Record?, causality: CausalSnapshot) throws {
        let payload = try canonicalPayload(context: context, entity: entity, entityID: entityID, operation: operation, record: record, causality: causality)
        try db.execute(sql: "INSERT INTO outbox (id, mutation_id, entity_type, entity_id, payload, status, created_at_ms) VALUES (?, ?, ?, ?, ?, 'pending', ?)", arguments: [UUID().uuidString, context.id, entity, entityID, payload, context.timestamp])
    }

    static func canonicalPayload<Record: Encodable>(context: MutationContext, entity: String, entityID: String, operation: String, record: Record?, causality: CausalSnapshot) throws -> Data {
        // sortedKeys yields stable bytes regardless of dictionary iteration order.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(CanonicalMutation(id: context.id, deviceID: context.deviceID, timestamp: context.timestamp, entityType: entity, entityID: entityID, operation: operation, record: record, causality: causality))
    }

    static func causality(from payload: Data) throws -> CausalSnapshot {
        try JSONDecoder().decode(CausalityProjection.self, from: payload).causality
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
    let causality: CausalSnapshot
}

private struct CausalityProjection: Decodable {
    let causality: CausalSnapshot
}
