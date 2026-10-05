import Foundation
import GRDB
import TaisaSecurity
import TaisaStorage

/// Owns one local store's sync turn. The transport sees ciphertext and opaque IDs only.
public actor SyncCoordinator {
    private let store: TaisaStore
    private let vault: Vault
    private let transport: any SyncTransport
    private let nowMS: @Sendable () -> Int64
    private let journal: ChangeJournal
    private var status: SyncState = .idle

    public init(store: TaisaStore, vault: Vault, transport: any SyncTransport,
                nowMS: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }) {
        self.store = store
        self.vault = vault
        self.transport = transport
        self.nowMS = nowMS
        self.journal = ChangeJournal(store: store)
    }

    public var currentState: SyncState { status }

    /// Resolution is a normal local mutation: domain state, conflict state,
    /// causality and the outgoing journal entry share one SQL transaction.
    public func resolveConflict(_ conflict: SyncConflict, using mutation: SyncMutation) async throws {
        let timestamp = max(nowMS(), mutation.timestampMS)
        try await store.write { db in
            let state = try Row.fetchOne(db, sql: "SELECT engine_state FROM sync_state WHERE id = 1")
            let prior: Data? = state?["engine_state"]
            let checkpoint = try prior.map { try JSONDecoder().decode(SyncEngineCheckpoint.self, from: $0) } ?? SyncEngineCheckpoint()
            let localRows = try Row.fetchAll(db, sql: "SELECT payload FROM outbox")
            let local = try localRows.map { row -> SyncProjection in
                let data: Data = row["payload"]
                return try SyncProjection(data)
            }
            let remote = try checkpoint.received.values.map(SyncProjection.init)
            let events = (local + remote).map(\.mutation).filter {
                $0.entityType == mutation.entityType && $0.entityID == mutation.entityID
            } + [mutation]
            let decision = try MergeEngine.reduce(events: events)
            let payload = try SyncProjection.journalPayload(for: mutation, decision: decision)
            try ConflictStore.resolve(conflict, using: mutation, at: timestamp, in: db)
            try SyncEntityShape.materialize(decision, entityType: mutation.entityType, entityID: mutation.entityID, in: db)
            try SyncEntityShape.retainCausality(mutation, in: db)
            try db.execute(sql: "INSERT INTO outbox (id, mutation_id, entity_type, entity_id, payload, status, created_at_ms) VALUES (?, ?, ?, ?, ?, 'pending', ?)", arguments: [UUID().uuidString, mutation.id, mutation.entityType, mutation.entityID, payload, mutation.timestampMS])
        }
    }

    public func synchronize(reason: SyncReason) async -> SyncOutcome {
        _ = reason
        if Task.isCancelled { status = .retrying; return SyncOutcome(state: status) }
        status = .syncing
        switch await transport.accountState() {
        case .offline: status = .offline; return SyncOutcome(state: status)
        case .noAccount: status = .noAccount; return SyncOutcome(state: status)
        case .unavailable: status = .unavailable; return SyncOutcome(state: status)
        case .available(let fingerprint):
            guard !fingerprint.isEmpty else { status = .recoveryRequired; return SyncOutcome(state: status) }
            do {
                let (token, retryAtMS) = try await bindAccount(fingerprint)
                if let retryAtMS, max(nowMS(), 0) < retryAtMS {
                    status = .retrying
                    return SyncOutcome(state: status, retryAtMS: retryAtMS)
                }
                return await runTurn(token: token, fingerprint: fingerprint)
            } catch SyncTransportError.accountChanged {
                status = .accountChanged
                return SyncOutcome(state: status)
            } catch {
                status = .recoveryRequired
                return SyncOutcome(state: status)
            }
        }
    }

    private func bindAccount(_ fingerprint: Data) async throws -> (Data?, Int64?) {
        let vaultID = vault.id.uuidString
        let timestamp = max(nowMS(), 0)
        return try await store.write { db in
            if let row = try Row.fetchOne(db, sql: "SELECT vault_id, account_fingerprint, change_token, engine_state FROM sync_state WHERE id = 1") {
                let storedVault: String? = row["vault_id"]
                let storedAccount: Data? = row["account_fingerprint"]
                guard storedVault == vaultID, storedAccount == fingerprint else { throw SyncTransportError.accountChanged }
                let checkpointData: Data? = row["engine_state"]
                let checkpoint = try checkpointData.map { try JSONDecoder().decode(SyncEngineCheckpoint.self, from: $0) }
                return (row["change_token"] as Data?, checkpoint?.retryAtMS)
            }
            try db.execute(sql: "INSERT INTO sync_state (id, vault_id, account_fingerprint, updated_at_ms) VALUES (1, ?, ?, ?)", arguments: [vaultID, fingerprint, timestamp])
            return (nil, nil)
        }
    }

    private func runTurn(token: Data?, fingerprint: Data) async -> SyncOutcome {
        var uploaded = 0
        var downloaded = 0
        var conflicts = 0
        var durableToken = token
        do {
            while !Task.isCancelled {
                try await ensureAccount(fingerprint)
                let reserved = try await journal.reservePending(limit: 200, at: max(nowMS(), 0), leaseDurationMS: 60_000)
                if reserved.isEmpty { break }
                let changes = try reserved.map { item -> EncryptedChange in
                    let change = item.change
                    guard let recordID = UUID(uuidString: change.id) else { throw SyncTransportError.permission }
                    let metadata = EnvelopeMetadata(vaultID: vault.id, recordID: recordID, entityType: change.entityType, schemaVersion: 1, tombstone: Self.isDeletion(change.payload))
                    return EncryptedChange(id: change.id, envelope: try vault.seal(change.payload, metadata: metadata))
                }
                let sent: SyncSendResult
                do {
                    try await ensureAccount(fingerprint)
                    sent = try await transport.send(changes)
                    try await ensureAccount(fingerprint)
                }
                catch {
                    for item in reserved { try await journal.retry(id: item.change.id, category: Self.retryCategory(error), reservationID: item.reservationID) }
                    throw error
                }
                let selected = Set(reserved.map { $0.change.id })
                let acknowledged = Set(sent.acknowledgedIDs)
                guard acknowledged.count == sent.acknowledgedIDs.count,
                      acknowledged.isSubset(of: selected),
                      Set(sent.failures.keys).isSubset(of: selected),
                      acknowledged.isDisjoint(with: Set(sent.failures.keys)) else { throw SyncTransportError.permission }
                for item in reserved {
                    if acknowledged.contains(item.change.id) {
                        try await journal.acknowledge(id: item.change.id, at: max(nowMS(), 0))
                        uploaded += 1
                    } else {
                        let category = Self.retryCategory(sent.failures[item.change.id] ?? SyncTransportError.retryable)
                        try await journal.retry(id: item.change.id, category: category, reservationID: item.reservationID)
                    }
                }
                if !sent.failures.isEmpty || acknowledged.count != reserved.count {
                    let error = sent.failures.values.first ?? .retryable
                    return await failed(error, uploaded: uploaded, downloaded: downloaded, attempts: (reserved.first?.change.attempts ?? 0) + 1)
                }
                if reserved.count < 200 { break }
            }
            var reconciling = false
            var pageCount = 0
            while !Task.isCancelled {
                try await ensureAccount(fingerprint)
                let page: SyncFetchPage
                do { page = try await transport.fetch(after: durableToken) }
                catch SyncTransportError.tokenExpired where !reconciling {
                    // The old durable token remains intact until a fetched page
                    // and its materialized records commit together.
                    reconciling = true
                    durableToken = nil
                    continue
                }
                pageCount += 1
                try await ensureAccount(fingerprint)
                guard pageCount <= 1_000,
                      !page.hasMore || page.token != durableToken else { throw SyncTransportError.retryable }
                if Task.isCancelled {
                    status = .retrying
                    return SyncOutcome(state: status, uploaded: uploaded, downloaded: downloaded)
                }
                var records: [(EncryptedChange, Data)] = []
                for change in page.changes {
                    do {
                        guard change.id == change.envelope.metadata.recordID.uuidString else { throw SyncTransportError.permission }
                        let plaintext = try vault.open(change.envelope)
                        let projection = try SyncProjection(plaintext)
                        guard projection.mutation.id == change.id,
                              projection.mutation.entityType == change.envelope.metadata.entityType,
                              (projection.mutation.kind == .delete) == change.envelope.metadata.tombstone else { throw SyncTransportError.permission }
                        records.append((change, plaintext))
                    } catch {
                        try await quarantine([change])
                        status = .recoveryRequired
                        return SyncOutcome(state: status, uploaded: uploaded, downloaded: downloaded, quarantined: 1)
                    }
                }
                conflicts += try await apply(records, token: page.token)
                downloaded += page.changes.count
                durableToken = page.token
                if !page.hasMore { break }
            }
            if Task.isCancelled { status = .retrying; return SyncOutcome(state: status, uploaded: uploaded, downloaded: downloaded) }
            let unresolved = try await ConflictStore(store: store).unresolved().count
            let outstanding = try await store.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM outbox WHERE status != 'acknowledged'") ?? 0
            }
            status = unresolved > 0 ? .conflictsNeedReview : (outstanding > 0 ? .retrying : .upToDate)
            return SyncOutcome(state: status, uploaded: uploaded, downloaded: downloaded, conflicts: conflicts)
        } catch {
            return await failed(error, uploaded: uploaded, downloaded: downloaded)
        }
    }

    private func ensureAccount(_ expected: Data) async throws {
        switch await transport.accountState() {
        case .available(let observed) where observed == expected: return
        case .offline: throw SyncTransportError.offline
        default: throw SyncTransportError.accountChanged
        }
    }

    private func apply(_ records: [(EncryptedChange, Data)], token: Data?) async throws -> Int {
        let timestamp = max(nowMS(), 0)
        return try await store.write { db in
            let state = try Row.fetchOne(db, sql: "SELECT engine_state FROM sync_state WHERE id = 1")
            let prior: Data? = state?["engine_state"]
            var checkpoint = try prior.map { try JSONDecoder().decode(SyncEngineCheckpoint.self, from: $0) } ?? SyncEngineCheckpoint()
            var received = checkpoint.received
            var affected: Set<String> = []
            for (change, plaintext) in records {
                let projection = try SyncProjection(plaintext)
                let mutation = projection.mutation
                guard mutation.id == change.id,
                      mutation.entityType == change.envelope.metadata.entityType,
                      (mutation.kind == .delete) == change.envelope.metadata.tombstone else { throw SyncTransportError.permission }
                if let previous = received[change.id], previous != plaintext { throw SyncTransportError.permission }
                received[change.id] = plaintext
                affected.insert(mutation.entityType + "|" + mutation.entityID)
            }
            let localRows = try Row.fetchAll(db, sql: "SELECT payload FROM outbox")
            let local = try localRows.map { row -> SyncProjection in
                let data: Data = row["payload"]
                return try SyncProjection(data)
            }
            let remote = try received.values.map(SyncProjection.init)
            let sources = local + remote
            var conflictCount = 0
            let order = ["profile", "conversation", "goal", "memory", "message", "milestone", "action", "evidence", "memory_source"]
            for key in affected.sorted(by: { left, right in
                let a = left.split(separator: "|", maxSplits: 1).first.map(String.init) ?? ""
                let b = right.split(separator: "|", maxSplits: 1).first.map(String.init) ?? ""
                return (order.firstIndex(of: a) ?? 99, left) < (order.firstIndex(of: b) ?? 99, right)
            }) {
                let events = sources.filter { $0.mutation.entityType + "|" + $0.mutation.entityID == key }.map(\.mutation)
                guard let first = events.first else { continue }
                let decision = try MergeEngine.reduce(events: events)
                try SyncEntityShape.materialize(decision, entityType: first.entityType, entityID: first.entityID, in: db)
                for resolution in events where resolution.kind == .resolve || (resolution.kind == .delete && resolution.resolvedParentVersionIDs != nil) {
                    let parents = Set(resolution.resolvedParentVersionIDs ?? [])
                    let rows = try Row.fetchAll(db, sql: "SELECT field_name, local_version_id, remote_version_id, local_value, remote_value FROM conflicts WHERE entity_type = ? AND entity_id = ? COLLATE NOCASE AND resolved_at_ms IS NULL", arguments: [first.entityType, first.entityID])
                    for row in rows {
                        let name: String = row["field_name"]
                        let firstID: String = row["local_version_id"]
                        let secondID: String = row["remote_version_id"]
                        guard parents.contains(firstID), parents.contains(secondID),
                              resolution.kind == .delete || resolution.fields.contains(where: { $0.name == name }) else { continue }
                        let firstValue: Data = row["local_value"]
                        let secondValue: Data = row["remote_value"]
                        let conflict = SyncConflict(entityType: first.entityType, entityID: first.entityID, fieldName: name,
                            first: try JSONDecoder().decode(ConflictingValue.self, from: firstValue),
                            second: try JSONDecoder().decode(ConflictingValue.self, from: secondValue))
                        try ConflictStore.resolve(conflict, using: resolution, at: timestamp, in: db)
                    }
                }
                for conflict in decision.conflicts {
                    try ConflictStore.persist(conflict, at: timestamp, in: db)
                    conflictCount += 1
                }
                for event in events { try SyncEntityShape.retainCausality(event, in: db) }
            }
            checkpoint.received = received
            checkpoint.retryAtMS = nil
            let engine = try JSONEncoder().encode(checkpoint)
            try db.execute(sql: "UPDATE sync_state SET change_token = ?, engine_state = ?, updated_at_ms = ? WHERE id = 1", arguments: [token, engine, timestamp])
            guard db.changesCount == 1 else { throw SyncTransportError.permission }
            return conflictCount
        }
    }

    private func quarantine(_ changes: [EncryptedChange]) async throws {
        let timestamp = max(nowMS(), 0)
        try await store.write { db in
            for change in changes {
                try db.execute(sql: "INSERT OR IGNORE INTO inbox_quarantine (id, envelope_id, ciphertext, reason_code, received_at_ms) VALUES (?, ?, ?, 'invalid_envelope', ?)", arguments: [UUID().uuidString, change.id, change.envelope.ciphertext, timestamp])
            }
        }
    }

    private func failed(_ error: Error, uploaded: Int, downloaded: Int, attempts: Int = 0) async -> SyncOutcome {
        var deadline: Int64?
        switch error as? SyncTransportError {
        case .offline: status = .offline
        case .quota: status = .storageFull
        case .accountChanged: status = .accountChanged
        case .permission, .tokenExpired: status = .recoveryRequired
        case .zoneReset: status = .zoneReset
        case .rateLimited(let retryAfter):
            status = .retrying
            deadline = RetryPolicy.nextAttemptMS(nowMS: max(nowMS(), 0), attempts: attempts, retryAfterMS: retryAfter)
        case .retryable:
            status = .retrying
            deadline = RetryPolicy.nextAttemptMS(nowMS: max(nowMS(), 0), attempts: attempts)
        case .none: status = .recoveryRequired
        }
        if let retryDeadline = deadline {
            do {
                try await store.write { db in
                    let row = try Row.fetchOne(db, sql: "SELECT engine_state FROM sync_state WHERE id = 1")
                    let prior: Data? = row?["engine_state"]
                    var checkpoint = try prior.map { try JSONDecoder().decode(SyncEngineCheckpoint.self, from: $0) } ?? SyncEngineCheckpoint()
                    checkpoint.retryAtMS = retryDeadline
                    try db.execute(sql: "UPDATE sync_state SET engine_state = ? WHERE id = 1", arguments: [try JSONEncoder().encode(checkpoint)])
                }
            } catch { status = .recoveryRequired; deadline = nil }
        }
        return SyncOutcome(state: status, uploaded: uploaded, downloaded: downloaded, retryAtMS: deadline)
    }

    private static func retryCategory(_ error: Error) -> String {
        switch error as? SyncTransportError {
        case .offline: "offline"
        case .quota: "quota"
        case .rateLimited: "rate_limited"
        case .accountChanged: "account"
        default: "transport"
        }
    }

    private static func isDeletion(_ payload: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return false }
        return object["operation"] as? String == "delete"
    }
}
