import Foundation
import GRDB
import TaisaSecurity
import TaisaStorage

private enum SyncTurnError: Error { case superseded }

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

    /// Explicit recovery after the transport has recreated/verified its zone.
    /// Every retained local or received mutation is replayed before the durable
    /// reset flag can be cleared. Ordinary synchronize never clears it.
    public func reconcileZoneAfterReset() async -> SyncOutcome {
        guard case .available(let fingerprint) = await transport.accountState() else {
            status = .zoneReset
            return SyncOutcome(state: status)
        }
        do {
            let (boundToken, _, recovery, generation) = try await bindAccount(fingerprint)
            guard recovery == .zoneReset else { status = .recoveryRequired; return SyncOutcome(state: status) }
            let session = try await transport.bind(expectedFingerprint: fingerprint)
            let recoveryToken = try await store.write { db -> Data? in
                guard let row = try Row.fetchOne(db, sql: "SELECT engine_state, change_token FROM sync_state WHERE id = 1"),
                      let encoded: Data = row["engine_state"] else { throw SyncMergeError.persistenceFailed }
                let committedToken: Data? = row["change_token"]
                guard committedToken == boundToken else { throw SyncTurnError.superseded }
                var checkpoint = try JSONDecoder().decode(SyncEngineCheckpoint.self, from: encoded)
                guard checkpoint.recoveryState == .zoneReset, checkpoint.turnGeneration == generation else { throw SyncTurnError.superseded }
                if !checkpoint.recoveryPrepared {
                    for payload in checkpoint.received.values {
                        let projection = try SyncProjection(payload)
                        try db.execute(sql: "INSERT OR IGNORE INTO outbox (id, mutation_id, entity_type, entity_id, payload, status, created_at_ms) VALUES (?, ?, ?, ?, ?, 'pending', ?)", arguments: [UUID().uuidString, projection.mutation.id, projection.mutation.entityType, projection.mutation.entityID, payload, projection.mutation.timestampMS])
                    }
                    try db.execute(sql: "UPDATE outbox SET status = 'pending', retry_category = NULL, acknowledged_at_ms = NULL WHERE status = 'acknowledged'")
                    checkpoint.recoveryPrepared = true
                    checkpoint.retryAtMS = nil
                    checkpoint.retryAttempts = 0
                    try db.execute(sql: "UPDATE sync_state SET change_token = NULL, engine_state = ? WHERE id = 1", arguments: [try JSONEncoder().encode(checkpoint)])
                    return nil
                }
                return committedToken
            }
            let result = await runTurn(token: recoveryToken, session: session, generation: generation)
            guard result.state == .upToDate || result.state == .conflictsNeedReview else {
                status = .zoneReset
                return SyncOutcome(state: status, uploaded: result.uploaded, downloaded: result.downloaded, conflicts: result.conflicts)
            }
            try await ensureAccount(session, generation: generation)
            try await store.write { db in
                guard let encoded = try Data.fetchOne(db, sql: "SELECT engine_state FROM sync_state WHERE id = 1") else { throw SyncMergeError.persistenceFailed }
                var checkpoint = try JSONDecoder().decode(SyncEngineCheckpoint.self, from: encoded)
                guard checkpoint.recoveryState == .zoneReset,
                      (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM outbox WHERE status != 'acknowledged'") ?? 0) == 0 else { throw SyncMergeError.persistenceFailed }
                checkpoint.recoveryState = nil
                checkpoint.recoveryPrepared = false
                checkpoint.lastState = result.state
                try db.execute(sql: "UPDATE sync_state SET engine_state = ? WHERE id = 1", arguments: [try JSONEncoder().encode(checkpoint)])
            }
            status = result.state
            return result
        } catch {
            status = .zoneReset
            return SyncOutcome(state: status)
        }
    }

    /// Resolution is a normal local mutation: domain state, conflict state,
    /// causality and the outgoing journal entry share one SQL transaction.
    public func resolveConflict(_ conflict: SyncConflict, using mutation: SyncMutation) async throws {
        let timestamp = max(nowMS(), mutation.timestampMS)
        do { try await store.write { db in
            let state = try Row.fetchOne(db, sql: "SELECT engine_state, change_token FROM sync_state WHERE id = 1")
            let prior: Data? = state?["engine_state"]
            var checkpoint = try prior.map { try JSONDecoder().decode(SyncEngineCheckpoint.self, from: $0) } ?? SyncEngineCheckpoint()
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
            let sources = local + remote
            guard let creation = sources.first(where: { $0.mutation.kind == .create && $0.mutation.entityType == mutation.entityType && $0.mutation.entityID == mutation.entityID }) else { throw SyncMergeError.malformedMutation }
            let payload = try SyncProjection.journalPayload(for: mutation, decision: decision, fullFields: creation.fullFields)
            try ConflictStore.resolve(conflict, using: mutation, at: timestamp, in: db)
            try SyncEntityShape.materialize(decision, entityType: mutation.entityType, entityID: mutation.entityID, source: sources, in: db)
            try SyncEntityShape.retainCausality(mutation, in: db)
            try SyncEntityShape.retainVisibleTips(decision, entityType: mutation.entityType, entityID: mutation.entityID, in: db)
            Self.replaceVisibleFieldTips(for: mutation.entityType, entityID: mutation.entityID, decision: decision, checkpoint: &checkpoint)
            try db.execute(sql: "UPDATE sync_state SET engine_state = ? WHERE id = 1", arguments: [try JSONEncoder().encode(checkpoint)])
            try db.execute(sql: "INSERT INTO outbox (id, mutation_id, entity_type, entity_id, payload, status, created_at_ms) VALUES (?, ?, ?, ?, ?, 'pending', ?)", arguments: [UUID().uuidString, mutation.id, mutation.entityType, mutation.entityID, payload, mutation.timestampMS])
        } } catch let error as SyncMergeError { throw error }
        catch { throw SyncMergeError.persistenceFailed }
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
                let (token, retryAtMS, recoveryState, generation) = try await bindAccount(fingerprint)
                if let recoveryState {
                    status = recoveryState
                    return SyncOutcome(state: status)
                }
                if let retryAtMS, max(nowMS(), 0) < retryAtMS {
                    status = .retrying
                    return SyncOutcome(state: status, retryAtMS: retryAtMS)
                }
                let session = try await transport.bind(expectedFingerprint: fingerprint)
                return await runTurn(token: token, session: session, generation: generation)
            } catch SyncTransportError.accountChanged {
                status = .accountChanged
                return SyncOutcome(state: status)
            } catch {
                status = .recoveryRequired
                return SyncOutcome(state: status)
            }
        }
    }

    private func bindAccount(_ fingerprint: Data) async throws -> (Data?, Int64?, SyncState?, Int64) {
        let vaultID = vault.id.uuidString
        let timestamp = max(nowMS(), 0)
        return try await store.write { db in
            if let row = try Row.fetchOne(db, sql: "SELECT vault_id, account_fingerprint, change_token, engine_state FROM sync_state WHERE id = 1") {
                let storedVault: String? = row["vault_id"]
                let storedAccount: Data? = row["account_fingerprint"]
                guard storedVault == vaultID, storedAccount == fingerprint else { throw SyncTransportError.accountChanged }
                let checkpointData: Data? = row["engine_state"]
                var checkpoint = try checkpointData.map { try JSONDecoder().decode(SyncEngineCheckpoint.self, from: $0) } ?? SyncEngineCheckpoint()
                let (generation, overflow) = checkpoint.turnGeneration.addingReportingOverflow(1)
                guard !overflow else { throw SyncMergeError.persistenceFailed }
                checkpoint.turnGeneration = generation
                try db.execute(sql: "UPDATE sync_state SET engine_state = ? WHERE id = 1", arguments: [try JSONEncoder().encode(checkpoint)])
                return (row["change_token"] as Data?, checkpoint.retryAtMS, checkpoint.recoveryState, generation)
            }
            var checkpoint = SyncEngineCheckpoint()
            checkpoint.turnGeneration = 1
            try db.execute(sql: "INSERT INTO sync_state (id, vault_id, account_fingerprint, engine_state, updated_at_ms) VALUES (1, ?, ?, ?, ?)", arguments: [vaultID, fingerprint, try JSONEncoder().encode(checkpoint), timestamp])
            return (nil, nil, nil, 1)
        }
    }

    private func runTurn(token: Data?, session: SyncAccountSession, generation: Int64) async -> SyncOutcome {
        var uploaded = 0
        var downloaded = 0
        var conflicts = 0
        var durableToken = token
        var expectedCommitToken = token
        do {
            while !Task.isCancelled {
                try await ensureAccount(session, generation: generation)
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
                    try await ensureAccount(session, generation: generation)
                    sent = try await transport.send(changes, session: session)
                    try await ensureAccount(session, generation: generation)
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
                    let failures = Array(sent.failures.values)
                    let serverDeadline = failures.compactMap { failure -> Int64? in
                        if case .rateLimited(let deadline) = failure { return deadline }
                        return nil
                    }.max()
                    return await failed(Self.aggregateFailures(failures), uploaded: uploaded, downloaded: downloaded, generation: generation, serverDeadline: serverDeadline)
                }
                if reserved.count < 200 { break }
            }
            var reconciling = false
            var pageCount = 0
            var deferred: [(EncryptedChange, Data)] = []
            while !Task.isCancelled {
                try await ensureAccount(session, generation: generation)
                let page: SyncFetchPage
                do { page = try await transport.fetch(after: durableToken, session: session) }
                catch SyncTransportError.tokenExpired where !reconciling {
                    // The old durable token remains intact until a fetched page
                    // and its materialized records commit together.
                    reconciling = true
                    durableToken = nil
                    continue
                }
                pageCount += 1
                try await ensureAccount(session, generation: generation)
                guard pageCount <= 1_000,
                      !page.hasMore || page.token != durableToken else { throw SyncTransportError.retryable }
                if Task.isCancelled {
                    status = .retrying
                    return SyncOutcome(state: status, uploaded: uploaded, downloaded: downloaded)
                }
                var records: [(EncryptedChange, Data)] = []
                for change in page.changes {
                    do {
                        guard change.envelope.metadata.schemaVersion == 1 else { throw SyncMergeError.unsupportedVersion }
                        guard change.id == change.envelope.metadata.recordID.uuidString else { throw SyncTransportError.permission }
                        let plaintext = try vault.open(change.envelope)
                        let projection = try SyncProjection(plaintext)
                        guard projection.mutation.id == change.id,
                              projection.mutation.entityType == change.envelope.metadata.entityType,
                              (projection.mutation.kind == .delete) == change.envelope.metadata.tombstone else { throw SyncTransportError.permission }
                        records.append((change, plaintext))
                    } catch {
                        try await quarantine([change])
                        let failure = await failed(SyncTransportError.permission, uploaded: uploaded, downloaded: downloaded, generation: generation)
                        return SyncOutcome(state: failure.state, uploaded: uploaded, downloaded: downloaded, quarantined: 1)
                    }
                }
                let candidates = deferred + records
                do {
                conflicts += try await apply(candidates, token: page.token, expectedToken: expectedCommitToken, generation: generation)
                } catch SyncProjectionError.dependencyPending where page.hasMore {
                    deferred = candidates
                    durableToken = page.token
                    continue
                }
                downloaded += candidates.count
                deferred = []
                durableToken = page.token
                expectedCommitToken = page.token
                if !page.hasMore { break }
            }
            if Task.isCancelled { status = .retrying; return SyncOutcome(state: status, uploaded: uploaded, downloaded: downloaded) }
            let unresolved = try await ConflictStore(store: store).unresolved().count
            let outstanding = try await store.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM outbox WHERE status != 'acknowledged'") ?? 0
            }
            status = unresolved > 0 ? .conflictsNeedReview : (outstanding > 0 ? .retrying : .upToDate)
            try await persistLastState(status, generation: generation)
            return SyncOutcome(state: status, uploaded: uploaded, downloaded: downloaded, conflicts: conflicts)
        } catch SyncTurnError.superseded {
            let committed = (try? await store.read { db -> SyncState? in
                let encoded = try Data.fetchOne(db, sql: "SELECT engine_state FROM sync_state WHERE id = 1")
                return try encoded.flatMap { try JSONDecoder().decode(SyncEngineCheckpoint.self, from: $0).lastState }
            }) ?? nil
            status = committed ?? .retrying
            return SyncOutcome(state: status, uploaded: uploaded, downloaded: downloaded, conflicts: conflicts)
        } catch {
            if Task.isCancelled {
                status = .retrying
                return SyncOutcome(state: status, uploaded: uploaded, downloaded: downloaded)
            }
            return await failed(error, uploaded: uploaded, downloaded: downloaded, generation: generation)
        }
    }

    private func ensureAccount(_ session: SyncAccountSession, generation: Int64) async throws {
        let current = try await transport.bind(expectedFingerprint: session.fingerprint)
        guard current == session else { throw SyncTransportError.accountChanged }
        let currentGeneration = try await store.read { db -> Int64 in
            let encoded = try Data.fetchOne(db, sql: "SELECT engine_state FROM sync_state WHERE id = 1")
            return try encoded.map { try JSONDecoder().decode(SyncEngineCheckpoint.self, from: $0).turnGeneration } ?? 0
        }
        guard currentGeneration == generation else { throw SyncTurnError.superseded }
    }

    private func apply(_ records: [(EncryptedChange, Data)], token: Data?, expectedToken: Data?, generation: Int64) async throws -> Int {
        let timestamp = max(nowMS(), 0)
        return try await store.write { db in
            let state = try Row.fetchOne(db, sql: "SELECT engine_state, change_token FROM sync_state WHERE id = 1")
            let actualToken: Data? = state?["change_token"]
            guard actualToken == expectedToken else { throw SyncTurnError.superseded }
            let prior: Data? = state?["engine_state"]
            var checkpoint = try prior.map { try JSONDecoder().decode(SyncEngineCheckpoint.self, from: $0) } ?? SyncEngineCheckpoint()
            guard checkpoint.turnGeneration == generation else { throw SyncTurnError.superseded }
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
                try SyncEntityShape.materialize(decision, entityType: first.entityType, entityID: first.entityID, source: sources, in: db)
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
                try SyncEntityShape.retainVisibleTips(decision, entityType: first.entityType, entityID: first.entityID, in: db)
                Self.replaceVisibleFieldTips(for: first.entityType, entityID: first.entityID, decision: decision, checkpoint: &checkpoint)
            }
            checkpoint.received = received
            checkpoint.retryAtMS = nil
            checkpoint.retryAttempts = 0
            checkpoint.lastState = .syncing
            let engine = try JSONEncoder().encode(checkpoint)
            try db.execute(sql: "UPDATE sync_state SET change_token = ?, engine_state = ?, updated_at_ms = ? WHERE id = 1", arguments: [token, engine, timestamp])
            guard db.changesCount == 1 else { throw SyncTransportError.permission }
            return conflictCount
        }
    }

    private static func replaceVisibleFieldTips(for entityType: String, entityID: String, decision: MergeDecision, checkpoint: inout SyncEngineCheckpoint) {
        let prefix = entityType + "|" + entityID + "|"
        checkpoint.visibleFieldTips = checkpoint.visibleFieldTips.filter { !$0.key.hasPrefix(prefix) }
        for (field, tips) in decision.visibleFieldHeads where tips.count > 1 {
            checkpoint.visibleFieldTips[prefix + field] = tips
        }
    }

    private func persistLastState(_ state: SyncState, generation: Int64) async throws {
        try await store.write { db in
            let encoded = try Data.fetchOne(db, sql: "SELECT engine_state FROM sync_state WHERE id = 1")
            var checkpoint = try encoded.map { try JSONDecoder().decode(SyncEngineCheckpoint.self, from: $0) } ?? SyncEngineCheckpoint()
            guard checkpoint.turnGeneration == generation else { throw SyncTurnError.superseded }
            checkpoint.lastState = state
            try db.execute(sql: "UPDATE sync_state SET engine_state = ? WHERE id = 1", arguments: [try JSONEncoder().encode(checkpoint)])
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

    private func failed(_ error: Error, uploaded: Int, downloaded: Int, generation: Int64, serverDeadline: Int64? = nil) async -> SyncOutcome {
        var deadline: Int64?
        let now = max(nowMS(), 0)
        let retryable: Bool
        switch error as? SyncTransportError {
        case .offline: status = .offline; retryable = false
        case .quota: status = .storageFull; retryable = false
        case .accountChanged: status = .accountChanged; retryable = false
        case .permission, .tokenExpired: status = .recoveryRequired; retryable = false
        case .zoneReset: status = .zoneReset; retryable = false
        case .rateLimited(let retryAfter):
            status = .retrying
            retryable = true
            deadline = retryAfter
        case .retryable:
            status = .retrying
            retryable = true
        case .none: status = .recoveryRequired; retryable = false
        }
        do {
            let requested = max(deadline ?? 0, serverDeadline ?? 0)
            let recoveryStatus = status
            deadline = try await store.write { db in
                let row = try Row.fetchOne(db, sql: "SELECT engine_state FROM sync_state WHERE id = 1")
                let prior: Data? = row?["engine_state"]
                var checkpoint = try prior.map { try JSONDecoder().decode(SyncEngineCheckpoint.self, from: $0) } ?? SyncEngineCheckpoint()
                guard checkpoint.turnGeneration == generation else { throw SyncTurnError.superseded }
                if uploaded > 0 || downloaded > 0 { checkpoint.retryAttempts = 0 }
                if retryable {
                    let next = RetryPolicy.nextAttemptMS(nowMS: now, attempts: checkpoint.retryAttempts, retryAfterMS: requested == 0 ? nil : requested)
                    checkpoint.retryAttempts = min(checkpoint.retryAttempts + 1, 8)
                    checkpoint.retryAtMS = next
                } else {
                    checkpoint.retryAtMS = requested > now ? requested : nil
                    if (recoveryStatus == .zoneReset || recoveryStatus == .recoveryRequired), checkpoint.recoveryState != .zoneReset {
                        checkpoint.recoveryState = recoveryStatus
                    }
                }
                checkpoint.lastState = checkpoint.recoveryState ?? recoveryStatus
                try db.execute(sql: "UPDATE sync_state SET engine_state = ? WHERE id = 1", arguments: [try JSONEncoder().encode(checkpoint)])
                return checkpoint.retryAtMS
            }
        } catch SyncTurnError.superseded {
            status = (try? await store.read { db -> SyncState? in
                let encoded = try Data.fetchOne(db, sql: "SELECT engine_state FROM sync_state WHERE id = 1")
                return try encoded.flatMap { try JSONDecoder().decode(SyncEngineCheckpoint.self, from: $0).lastState }
            }) ?? .retrying
            deadline = nil
        } catch { status = .recoveryRequired; deadline = nil }
        return SyncOutcome(state: status, uploaded: uploaded, downloaded: downloaded, retryAtMS: deadline)
    }

    private static func aggregateFailures(_ failures: [SyncTransportError]) -> SyncTransportError {
        if failures.contains(.accountChanged) { return .accountChanged }
        if failures.contains(.permission) { return .permission }
        if failures.contains(.zoneReset) { return .zoneReset }
        if failures.contains(.quota) { return .quota }
        if failures.contains(.offline) { return .offline }
        let deadlines = failures.compactMap { error -> Int64? in
            if case .rateLimited(let deadline) = error { return deadline }
            return nil
        }
        if let longest = deadlines.max() { return .rateLimited(retryAfterMS: longest) }
        return .retryable
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
