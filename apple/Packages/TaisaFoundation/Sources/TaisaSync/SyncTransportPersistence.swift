import Foundation
import GRDB
import TaisaStorage

/// Keeps transport state beside the coordinator checkpoint in SQLCipher. The
/// coordinator owns `change_token`; advancing it acknowledges only records the
/// coordinator has authenticated and committed to the local store.
public actor SyncTransportPersistence {
    private let store: TaisaStore

    public init(store: TaisaStore) { self.store = store }

    public func engineState(for fingerprint: Data) async throws -> Data? {
        try await store.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT account_fingerprint, engine_state FROM sync_state WHERE id = 1"),
                  (row["account_fingerprint"] as Data?) == fingerprint,
                  let encoded: Data = row["engine_state"] else { throw SyncTransportError.accountChanged }
            return try JSONDecoder().decode(SyncEngineCheckpoint.self, from: encoded).cloudKitState
        }
    }

    public func saveEngineState(_ data: Data, for fingerprint: Data) async throws {
        try await mutate(for: fingerprint) { checkpoint in checkpoint.cloudKitState = data }
    }

    public func clearEngineState(for fingerprint: Data) async throws {
        try await mutate(for: fingerprint) { checkpoint in checkpoint.cloudKitState = nil }
    }

    public func append(_ changes: [EncryptedChange], for fingerprint: Data) async throws {
        guard !changes.isEmpty else { return }
        try await mutate(for: fingerprint) { checkpoint in
            for change in changes {
                let (next, overflow) = checkpoint.cloudKitNextSequence.addingReportingOverflow(1)
                guard !overflow else { throw SyncTransportError.permission }
                checkpoint.cloudKitNextSequence = next
                checkpoint.cloudKitInbox.append(CloudKitInboxItem(sequence: next, change: change))
            }
        }
    }

    public func page(after token: Data?, for fingerprint: Data, limit: Int = 200) async throws -> SyncFetchPage {
        guard limit > 0 && limit <= 200 else { throw SyncTransportError.permission }
        let cursor: Int64
        if let token {
            guard let value = String(data: token, encoding: .utf8).flatMap(Int64.init), value >= 0 else {
                throw SyncTransportError.tokenExpired
            }
            cursor = value
        } else { cursor = 0 }
        return try await store.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT account_fingerprint, engine_state, change_token FROM sync_state WHERE id = 1"),
                  (row["account_fingerprint"] as Data?) == fingerprint,
                  let encoded: Data = row["engine_state"] else { throw SyncTransportError.accountChanged }
            var checkpoint = try JSONDecoder().decode(SyncEngineCheckpoint.self, from: encoded)
            guard cursor <= checkpoint.cloudKitNextSequence else { throw SyncTransportError.tokenExpired }
            let committed: Int64
            if let committedData: Data = row["change_token"] {
                guard let value = String(data: committedData, encoding: .utf8).flatMap(Int64.init),
                      value >= 0, value <= checkpoint.cloudKitNextSequence else { throw SyncTransportError.tokenExpired }
                committed = value
            } else { committed = 0 }
            checkpoint.cloudKitInbox.removeAll { $0.sequence <= committed }
            let effectiveCursor = max(cursor, committed)
            let pending = checkpoint.cloudKitInbox.filter { $0.sequence > effectiveCursor }.prefix(limit)
            let last = pending.last?.sequence ?? effectiveCursor
            let hasMore = checkpoint.cloudKitInbox.contains { $0.sequence > last }
            try db.execute(sql: "UPDATE sync_state SET engine_state = ? WHERE id = 1", arguments: [try JSONEncoder().encode(checkpoint)])
            return SyncFetchPage(changes: pending.map(\.change), token: Data(String(last).utf8), hasMore: hasMore)
        }
    }

    private func mutate(for fingerprint: Data, _ body: @Sendable (inout SyncEngineCheckpoint) throws -> Void) async throws {
        try await store.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT account_fingerprint, engine_state FROM sync_state WHERE id = 1"),
                  (row["account_fingerprint"] as Data?) == fingerprint,
                  let encoded: Data = row["engine_state"] else { throw SyncTransportError.accountChanged }
            var checkpoint = try JSONDecoder().decode(SyncEngineCheckpoint.self, from: encoded)
            try body(&checkpoint)
            try db.execute(sql: "UPDATE sync_state SET engine_state = ? WHERE id = 1", arguments: [try JSONEncoder().encode(checkpoint)])
        }
    }
}
