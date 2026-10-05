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
            let cursor = try Row.fetchCursor(db, sql: "SELECT mutation_id, entity_type, entity_id, payload, created_at_ms, status, attempts, retry_category, acknowledged_at_ms FROM outbox WHERE status IN ('pending', 'retrying') ORDER BY rowid")
            var changes: [PendingChange] = []
            while changes.count < min(limit, 200), let row = try cursor.next() {
                try Self.requireUniqueMutation(row, db: db)
                let state = try Self.state(row)
                switch state {
                case .pending, .retrying:
                    changes.append(try Self.pendingChange(row, state: state))
                case .reserved:
                    continue
                case .superseded, .remotelyAcknowledged:
                    throw RepositoryError.persistenceFailed
                }
            }
            return changes
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
            let cursor = try Row.fetchCursor(db, sql: "SELECT mutation_id, entity_type, entity_id, payload, created_at_ms, status, attempts, retry_category, acknowledged_at_ms FROM outbox WHERE status IN ('pending', 'retrying') ORDER BY rowid")
            var selected: [(PendingChange, String, String?)] = []
            while selected.count < min(limit, 200), let row = try cursor.next() {
                try Self.requireUniqueMutation(row, db: db)
                let state = try Self.state(row)
                switch state {
                case .pending, .retrying:
                    break
                case .reserved(_, let deadline, _):
                    if deadline > timestamp { continue }
                case .superseded, .remotelyAcknowledged:
                    throw RepositoryError.persistenceFailed
                }
                selected.append((try Self.pendingChange(row, state: state), row["status"], row["retry_category"]))
            }
            return try selected.map { change, status, category in
                try db.execute(sql: "UPDATE outbox SET status = 'retrying', retry_category = ? WHERE mutation_id = ? COLLATE NOCASE AND status = ? AND retry_category IS ? AND acknowledged_at_ms IS NULL AND attempts = ?", arguments: [marker, change.id, status, category, change.attempts])
                guard db.changesCount == 1 else { throw RepositoryError.persistenceFailed }
                return ReservedChange(change: change, reservationID: reservationID, expiresAtMS: expiry)
            }
        }
    }

    public func acknowledge(id: String, at timestamp: Int64) async throws {
        guard timestamp >= 0 else { throw RepositoryError.invalidTimestamp }
        try await safeWrite { db in
            guard let row = try Self.uniqueMutationRow(id, db: db) else { return }
            let current = try Self.state(row)
            let prior: Int64? = row["acknowledged_at_ms"]
            let acknowledgedAt = max(timestamp, prior ?? timestamp)
            let status: String = row["status"]
            let category: String? = row["retry_category"]
            let attempts: Int = row["attempts"]
            switch current {
            case .superseded:
                // A stale uploader can still report a real remote success.
                try db.execute(sql: "UPDATE outbox SET acknowledged_at_ms = MAX(created_at_ms, ?) WHERE mutation_id = ? COLLATE NOCASE AND status = ? AND retry_category IS ? AND acknowledged_at_ms IS ? AND attempts = ?", arguments: [acknowledgedAt, id, status, category, prior, attempts])
            case .remotelyAcknowledged:
                return
            default:
                try db.execute(sql: "UPDATE outbox SET status = 'acknowledged', retry_category = NULL, acknowledged_at_ms = MAX(created_at_ms, ?) WHERE mutation_id = ? COLLATE NOCASE AND status = ? AND retry_category IS ? AND acknowledged_at_ms IS ? AND attempts = ?", arguments: [acknowledgedAt, id, status, category, prior, attempts])
            }
            guard db.changesCount == 1 else { throw RepositoryError.persistenceFailed }
        }
    }

    public func retry(id: String, category: String, reservationID: String? = nil) async throws {
        guard ["offline", "quota", "rate_limited", "transport", "account"].contains(category) else { throw RepositoryError.invalidIdentifier }
        let reservationID = try reservationID.map { try Self.requiredID($0) }
        try await safeWrite { db in
            guard let row = try Self.uniqueMutationRow(id, db: db) else { return }
            let current = try Self.state(row)
            switch current {
            case .reserved(let token, _, _):
                guard token == reservationID else { throw RepositoryError.reservationMismatch }
            case .pending, .retrying:
                guard reservationID == nil else { throw RepositoryError.reservationMismatch }
            case .superseded, .remotelyAcknowledged:
                return
            }
            let status: String = row["status"]
            let priorCategory: String? = row["retry_category"]
            let attempts: Int = row["attempts"]
            try db.execute(sql: "UPDATE outbox SET status = 'retrying', retry_category = ?, attempts = attempts + 1 WHERE mutation_id = ? COLLATE NOCASE AND status = ? AND retry_category IS ? AND acknowledged_at_ms IS NULL AND attempts = ?", arguments: [category, id, status, priorCategory, attempts])
            guard db.changesCount == 1 else { throw RepositoryError.persistenceFailed }
        }
    }

    public func state(id: String) async throws -> JournalState? {
        try await safeRead { db in
            guard let row = try Self.uniqueMutationRow(id, db: db) else { return nil }
            return try Self.state(row)
        }
    }

    /// Follows durable replacement links. Only a transport acknowledgement of
    /// this mutation or its surviving descendant confirms remote coverage.
    public func remoteCoverage(id: String) async throws -> JournalCoverage {
        try await safeRead { db in
            var current = try Self.requiredID(id)
            var visited: Set<String> = []
            while visited.insert(current).inserted, visited.count <= 10_000 {
                guard let row = try Self.uniqueMutationRow(current, db: db) else { return .unverifiable }
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
        let olderKey = try Self.requiredID(olderID), newerKey = try Self.requiredID(newerID)
        guard olderKey != newerKey, timestamp >= 0 else { return false }
        return try await safeWrite { db in
            guard let older = try Self.uniqueMutationRow(olderKey, db: db),
                  let newer = try Self.uniqueMutationRow(newerKey, db: db) else { return false }
            let olderState = try Self.state(older)
            let newerState = try Self.state(newer)
            guard case .pending = olderState, case .pending = newerState,
                  (older["entity_type"] as String) == (newer["entity_type"] as String),
                  try Self.requiredID(older["entity_id"] as String) == Self.requiredID(newer["entity_id"] as String),
                  operation(in: older["payload"] as Data) == "update",
                  operation(in: newer["payload"] as Data) == "update" else { return false }
            let changed = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM field_versions WHERE entity_type = ? AND entity_id = ? COLLATE NOCASE AND version_id = ? COLLATE NOCASE", arguments: [older["entity_type"] as String, older["entity_id"] as String, olderKey]) ?? 0
            let direct = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM field_versions WHERE entity_type = ? AND entity_id = ? COLLATE NOCASE AND parent_version_id = ? COLLATE NOCASE AND version_id = ? COLLATE NOCASE", arguments: [older["entity_type"] as String, older["entity_id"] as String, olderKey, newerKey]) ?? 0
            guard changed > 0, changed == direct else { return false }
            // The replacement link and nil timestamp distinguish local
            // coalescing from a confirmed remote acknowledgement in v1.
            let olderAttempts: Int = older["attempts"]
            try db.execute(sql: "UPDATE outbox SET status = 'acknowledged', retry_category = ?, acknowledged_at_ms = NULL WHERE mutation_id = ? COLLATE NOCASE AND status = 'pending' AND retry_category IS NULL AND acknowledged_at_ms IS NULL AND attempts = ?", arguments: ["superseded:\(newerKey)", olderKey, olderAttempts])
            guard db.changesCount == 1 else { throw RepositoryError.persistenceFailed }
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

    private static func pendingChange(_ row: Row, state: JournalState) throws -> PendingChange {
        let storedPayload: Data = row["payload"]
        let normalizedPayload = try normalizedPayload(storedPayload)
        let payload = normalizedPayload.changed ? normalizedPayload.data : storedPayload
        let category: String?
        switch state {
        case .pending, .reserved: category = nil
        case .retrying(let retryCategory, _): category = retryCategory
        case .superseded, .remotelyAcknowledged: throw RepositoryError.persistenceFailed
        }
        return PendingChange(id: try requiredID(row["mutation_id"]), entityType: row["entity_type"], entityID: try requiredID(row["entity_id"]), payload: payload, createdAtMS: row["created_at_ms"], attempts: row["attempts"], retryCategory: category, causality: try canonicalCausality(causality(from: payload)))
    }

    private static func requiredID(_ raw: String) throws -> String {
        guard let canonical = UUIDIdentity.canonical(raw) else { throw RepositoryError.invalidIdentifier }
        return canonical
    }

    /// Only identity-bearing JSON paths are normalized; UUID-shaped user text
    /// remains untouched. Stored legacy bytes remain immutable, while public
    /// upload bytes use the canonical identity spelling.
    static func normalizedPayload(_ payload: Data) throws -> (data: Data, changed: Bool) {
        guard var object = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
              var causal = object["causality"] as? [String: Any] else { throw RepositoryError.persistenceFailed }
        let original = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        func normalize(_ key: String, in object: inout [String: Any]) throws {
            if let raw = object[key] as? String {
                guard let value = UUIDIdentity.canonical(raw) else { throw RepositoryError.persistenceFailed }
                object[key] = value
            }
        }
        for key in ["id", "deviceID", "entityID"] { try normalize(key, in: &object) }
        if var record = object["record"] as? [String: Any] {
            for key in ["id", "conversationID", "goalID", "actionID", "memoryItemID", "sourceID"] { try normalize(key, in: &record) }
            object["record"] = record
        }
        for key in ["logicalVersionID", "recordParentVersionID", "deviceID"] { try normalize(key, in: &causal) }
        if let parents = causal["resolvedParentVersionIDs"] as? [String] {
            causal["resolvedParentVersionIDs"] = try parents.map { raw in
                guard let value = UUIDIdentity.canonical(raw) else { throw RepositoryError.persistenceFailed }
                return value
            }
        }
        if var retained = causal["retainedDeletionCausality"] as? [String: Any] {
            if let versions = retained["versionIDs"] as? [String] {
                retained["versionIDs"] = try versions.map { raw in
                    guard let value = UUIDIdentity.canonical(raw) else { throw RepositoryError.persistenceFailed }
                    return value
                }
            }
            if var frontier = retained["frontier"] as? [[String: Any]] {
                for index in frontier.indices { try normalize("deviceID", in: &frontier[index]) }
                retained["frontier"] = frontier
            }
            if var fields = retained["observedFieldVersions"] as? [[String: Any]] {
                for index in fields.indices { try normalize("versionID", in: &fields[index]) }
                retained["observedFieldVersions"] = fields
            }
            causal["retainedDeletionCausality"] = retained
        }
        if var fields = causal["changedFields"] as? [[String: Any]] {
            for index in fields.indices {
                try normalize("versionID", in: &fields[index])
                try normalize("parentVersionID", in: &fields[index])
                if let ancestors = fields[index]["ancestorVersionIDs"] as? [String] {
                    fields[index]["ancestorVersionIDs"] = try ancestors.map { raw in
                        guard let value = UUIDIdentity.canonical(raw) else { throw RepositoryError.persistenceFailed }
                        return value
                    }
                }
            }
            causal["changedFields"] = fields
        }
        if var fields = causal["observedFieldVersions"] as? [[String: Any]] {
            for index in fields.indices { try normalize("versionID", in: &fields[index]) }
            causal["observedFieldVersions"] = fields
        }
        object["causality"] = causal
        let normalized = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return (normalized, normalized != original)
    }

    private static func requireUniqueMutation(_ row: Row, db: Database) throws {
        let key = try requiredID(row["mutation_id"])
        let matches = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM outbox WHERE mutation_id = ? COLLATE NOCASE", arguments: [key]) ?? 0
        guard matches == 1 else { throw RepositoryError.persistenceFailed }
        try requireUnambiguousEntity(row, db: db)
    }

    private static func uniqueMutationRow(_ id: String, db: Database) throws -> Row? {
        let key = try requiredID(id)
        let matches = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM outbox WHERE mutation_id = ? COLLATE NOCASE", arguments: [key]) ?? 0
        guard matches <= 1 else { throw RepositoryError.persistenceFailed }
        let row = try Row.fetchOne(db, sql: "SELECT * FROM outbox WHERE mutation_id = ? COLLATE NOCASE", arguments: [key])
        if let row { try requireUnambiguousEntity(row, db: db) }
        return row
    }

    private static func requireUnambiguousEntity(_ row: Row, db: Database) throws {
        let entityType: String = row["entity_type"]
        guard let kind = DomainEntity(rawValue: entityType) else { throw RepositoryError.persistenceFailed }
        let entityID = try requiredID(row["entity_id"] as String)
        let matches = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(kind.table) WHERE id = ? COLLATE NOCASE", arguments: [entityID]) ?? 0
        guard matches <= 1 else { throw RepositoryError.persistenceFailed }
        guard !kind.references.isEmpty else { return }
        let storedRecord = try Row.fetchOne(db, sql: "SELECT * FROM \(kind.table) WHERE id = ? COLLATE NOCASE", arguments: [entityID])
        let payload: Data = row["payload"]
        guard let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else { throw RepositoryError.persistenceFailed }
        let record = object["record"] as? [String: Any]
        for (property, column, table) in kind.references {
            var parentsToCheck: Set<String> = []
            if let parent = record?[property] as? String { try parentsToCheck.insert(requiredID(parent)) }
            if let storedRecord, let storedParent: String = storedRecord[column] { try parentsToCheck.insert(requiredID(storedParent)) }
            for parentID in parentsToCheck {
                let parents = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table) WHERE id = ? COLLATE NOCASE", arguments: [parentID]) ?? 0
                guard parents <= 1 else { throw RepositoryError.persistenceFailed }
            }
        }
    }

    static func canonicalCausality(_ snapshot: CausalSnapshot) throws -> CausalSnapshot {
        try CausalSnapshot(
            logicalVersionID: requiredID(snapshot.logicalVersionID),
            recordParentVersionID: snapshot.recordParentVersionID.map { try requiredID($0) },
            resolvedParentVersionIDs: try snapshot.resolvedParentVersionIDs?.map { try requiredID($0) },
            retainedDeletionCausality: try snapshot.retainedDeletionCausality.map { retained in
                RetainedDeletionCausality(versionIDs: try retained.versionIDs.map { try requiredID($0) }, latestDeletedAtMS: retained.latestDeletedAtMS, frontier: try retained.frontier.map { CausalDeviceCounter(deviceID: try requiredID($0.deviceID), counter: $0.counter) }, observedFieldVersions: try retained.observedFieldVersions.map { ObservedFieldVersion(fieldName: $0.fieldName, versionID: try requiredID($0.versionID)) })
            },
            deviceID: requiredID(snapshot.deviceID),
            deviceCounter: snapshot.deviceCounter,
            changedFields: snapshot.changedFields.map { field in
                try FieldCausalVersion(fieldName: field.fieldName, versionID: requiredID(field.versionID), parentVersionID: field.parentVersionID.map { try requiredID($0) }, ancestorVersionIDs: field.ancestorVersionIDs.map { try requiredID($0) }, deviceCounter: field.deviceCounter)
            },
            observedFieldVersions: snapshot.observedFieldVersions.map { field in
                try ObservedFieldVersion(fieldName: field.fieldName, versionID: requiredID(field.versionID))
            }
        )
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
        guard attempts >= 0 else { throw RepositoryError.persistenceFailed }
        switch status {
        case "pending":
            guard category == nil, acknowledgedAt == nil else { throw RepositoryError.persistenceFailed }
            return .pending
        case "retrying":
            guard acknowledgedAt == nil, let category else { throw RepositoryError.persistenceFailed }
            if category.hasPrefix("reserved:") {
                let parts = category.split(separator: ":", omittingEmptySubsequences: false)
                guard parts.count == 3, parts[1].count == 20,
                      parts[1].allSatisfy({ $0 >= "0" && $0 <= "9" }),
                      let expiry = Int64(parts[1]), expiry > 0,
                      let token = UUIDIdentity.canonical(String(parts[2])),
                      reservationMarker(id: token, expiresAtMS: expiry).lowercased() == category.lowercased() else { throw RepositoryError.persistenceFailed }
                return .reserved(reservationID: token, expiresAtMS: expiry, attempts: attempts)
            }
            guard ["offline", "quota", "rate_limited", "transport", "account"].contains(category) else { throw RepositoryError.persistenceFailed }
            return .retrying(category: category, attempts: attempts)
        case "acknowledged":
            if let category, category.hasPrefix("superseded:") {
                let replacement = String(category.dropFirst("superseded:".count))
                guard let canonical = UUIDIdentity.canonical(replacement) else { throw RepositoryError.persistenceFailed }
                return .superseded(by: canonical, remotelyAcknowledgedAtMS: acknowledgedAt)
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
