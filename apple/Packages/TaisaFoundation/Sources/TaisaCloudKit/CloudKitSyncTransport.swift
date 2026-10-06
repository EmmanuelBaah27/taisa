import CloudKit
import CryptoKit
import Foundation
import TaisaStorage
import TaisaSync

struct CloudKitEngineHandle: @unchecked Sendable {
    let id = UUID()
    let native: CKSyncEngine?
    init(native: CKSyncEngine? = nil) { self.native = native }
}

struct CloudKitRecordSaveFailure: Sendable {
    let record: CKRecord
    let error: CKError
}

/// The live bridge owns system CloudKit objects. Tests provide the same
/// operation/event boundary without constructing a signed CKContainer.
struct CloudKitTransportRuntime: Sendable {
    let accountState: @Sendable () async throws -> SyncAccountState
    let makeEngine: @Sendable (Data?, CloudKitSyncTransport) throws -> CloudKitEngineHandle
    let send: @Sendable (CloudKitEngineHandle, [CKRecord]) async throws -> Void
    let fetch: @Sendable (CloudKitEngineHandle) async throws -> Void
    let cancel: @Sendable (CloudKitEngineHandle) async -> Void

    static func live(containerIdentifier: String) -> Self {
        let container = CKContainer(identifier: containerIdentifier)
        return Self(
            accountState: {
                switch try await container.accountStatus() {
                case .available:
                    let user = try await container.userRecordID()
                    return .available(fingerprint: Data(SHA256.hash(data: Data(user.recordName.utf8))))
                case .noAccount: return .noAccount
                default: return .unavailable
                }
            },
            makeEngine: { serialized, delegate in
                var configuration = CKSyncEngine.Configuration(
                    database: container.privateCloudDatabase,
                    stateSerialization: try CloudKitEngineStateCodec.decode(serialized),
                    delegate: delegate
                )
                configuration.automaticallySync = false
                configuration.subscriptionID = "TaisaVaultV1Changes"
                return CloudKitEngineHandle(native: CKSyncEngine(configuration))
            },
            send: { handle, records in
                guard let native = handle.native else { throw SyncTransportError.retryable }
                let zone = CKRecordZone(zoneID: CloudRecordMapper.zoneID)
                native.state.add(pendingDatabaseChanges: [.saveZone(zone)])
                native.state.add(pendingRecordZoneChanges: records.map { .saveRecord($0.recordID) })
                try await native.sendChanges()
            },
            fetch: { handle in
                guard let native = handle.native else { throw SyncTransportError.retryable }
                try await native.fetchChanges()
            },
            cancel: { handle in
                if let native = handle.native { await native.cancelOperations() }
            }
        )
    }
}

/// Async actor methods are reentrant. Hold this lease across the complete
/// CKSyncEngine call and all of its callback/result processing.
actor CloudKitOperationIsolation {
    private var active = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<Value: Sendable>(_ body: @Sendable () async throws -> Value) async throws -> Value {
        if active {
            await withCheckedContinuation { waiters.append($0) }
            if Task.isCancelled {
                release()
                throw CancellationError()
            }
        } else { active = true }
        defer { release() }
        try Task.checkCancellation()
        let value = try await body()
        try Task.checkCancellation()
        return value
    }

    private func release() {
        if waiters.isEmpty { active = false }
        else { waiters.removeFirst().resume() }
    }
}

/// Each upload owns only its own ciphertext staging directory.
struct CloudKitAssetLease: Sendable {
    let directory: URL
    init(root: URL) { directory = root.appendingPathComponent(UUID().uuidString) }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

struct CloudKitAccountBinding: Sendable {
    private(set) var fingerprint: Data?
    private(set) var generation = UUID()

    mutating func observeAvailable(_ observed: Data) -> Bool {
        let changed = fingerprint != nil && fingerprint != observed
        if changed { generation = UUID() }
        fingerprint = observed
        return changed
    }

    mutating func observeNoAccount() -> Bool {
        let changed = fingerprint != nil
        if changed { generation = UUID() }
        fingerprint = nil
        return changed
    }

    mutating func invalidate() {
        generation = UUID()
        fingerprint = nil
    }

    mutating func rotateGeneration() { generation = UUID() }

    func matches(_ session: SyncAccountSession) -> Bool {
        fingerprint == session.fingerprint && generation == session.generation
    }
}

/// A private-database CKSyncEngine adapter. The coordinator sees only sealed
/// `EncryptedChange` values and SQLCipher-backed transport tokens.
public actor CloudKitSyncTransport: SyncTransport, CKSyncEngineDelegate {
    private let persistence: SyncTransportPersistence
    private let assetRoot: URL
    private let runtime: CloudKitTransportRuntime
    private let operationIsolation = CloudKitOperationIsolation()
    private var engine: CloudKitEngineHandle?
    private var account = CloudKitAccountBinding()
    private var outgoing: [CKRecord.ID: CKRecord] = [:]
    private var acknowledged: [String] = []
    private var failures: [String: SyncTransportError] = [:]
    private var serverConflicts: [String: EncryptedChange] = [:]
    private var eventError: SyncTransportError?
    private var needsFullReconciliation = false

    public init(containerIdentifier: String, bundleIdentifier: String, store: TaisaStore) throws {
        guard Self.approvedContainer(for: bundleIdentifier) == containerIdentifier else {
            throw SyncTransportError.permission
        }
        try self.init(containerIdentifier: containerIdentifier, bundleIdentifier: bundleIdentifier,
                      store: store, runtime: .live(containerIdentifier: containerIdentifier))
    }

    init(containerIdentifier: String, bundleIdentifier: String, store: TaisaStore,
         runtime: CloudKitTransportRuntime, assetRoot: URL? = nil) throws {
        guard Self.approvedContainer(for: bundleIdentifier) == containerIdentifier else { throw SyncTransportError.permission }
        persistence = SyncTransportPersistence(store: store)
        self.runtime = runtime
        self.assetRoot = assetRoot ?? FileManager.default.temporaryDirectory.appendingPathComponent("taisa-cloudkit-\(UUID().uuidString)")
    }

    public func accountState() async -> SyncAccountState {
        do {
            let state = try await runtime.accountState()
            switch state {
            case .available(let observed):
                if account.observeAvailable(observed) {
                    await discardEngine()
                    needsFullReconciliation = false
                }
                return .available(fingerprint: observed)
            case .noAccount:
                if account.observeNoAccount() { await discardEngine() }
                needsFullReconciliation = false
                return .noAccount
            default: return state
            }
        } catch {
            let mapped = CloudKitErrorMapper.map(error)
            return mapped == .offline ? .offline : .unavailable
        }
    }

    public func bind(expectedFingerprint: Data) async throws -> SyncAccountSession {
        guard case .available(let observed) = await accountState(), observed == expectedFingerprint else {
            throw SyncTransportError.accountChanged
        }
        if engine == nil {
            let boundGeneration = account.generation
            let serialized = try await persistence.engineState(for: observed)
            guard account.fingerprint == observed, account.generation == boundGeneration else { throw SyncTransportError.accountChanged }
            if engine == nil { engine = try runtime.makeEngine(serialized, self) }
        }
        return SyncAccountSession(fingerprint: observed, generation: account.generation)
    }

    public func send(_ changes: [EncryptedChange], session: SyncAccountSession) async throws -> SyncSendResult {
        try await operationIsolation.run { try await self.sendLocked(changes, session: session) }
    }

    private func sendLocked(_ changes: [EncryptedChange], session: SyncAccountSession) async throws -> SyncSendResult {
        try await require(session)
        guard changes.count <= 200 else { throw SyncTransportError.permission }
        guard let activeEngine = engine else { throw SyncTransportError.retryable }
        try Task.checkCancellation()
        acknowledged = []
        failures = [:]
        serverConflicts = [:]
        eventError = nil
        let operationAssets = CloudKitAssetLease(root: assetRoot)
        defer {
            outgoing = [:]
            operationAssets.cleanup()
        }
        for change in changes {
            let record = try CloudRecordMapper.makeRecord(change, assetDirectory: operationAssets.directory)
            outgoing[record.recordID] = record
        }
        let operationRuntime = runtime
        do {
            try await withTaskCancellationHandler {
                try await operationRuntime.send(activeEngine, Array(outgoing.values))
            } onCancel: {
                Task { await operationRuntime.cancel(activeEngine) }
            }
        }
        catch {
            if Task.isCancelled {
                await discardEngine()
                throw CancellationError()
            }
            let mapped = CloudKitErrorMapper.map(error)
            guard mapped != .accountChanged, !acknowledged.isEmpty || !failures.isEmpty else { throw mapped }
            let known = Set(acknowledged).union(failures.keys)
            for change in changes where !known.contains(change.id) { failures[change.id] = mapped }
        }
        if Task.isCancelled {
            await discardEngine()
            throw CancellationError()
        }
        try await require(session)
        if let eventError {
            if eventError == .accountChanged { await retireEngine() }
            else { await discardEngine() }
            throw eventError
        }
        return SyncSendResult(acknowledgedIDs: acknowledged, failures: failures, serverConflicts: serverConflicts)
    }

    public func fetch(after token: Data?, session: SyncAccountSession) async throws -> SyncFetchPage {
        try await operationIsolation.run { try await self.fetchLocked(after: token, session: session) }
    }

    private func fetchLocked(after token: Data?, session: SyncAccountSession) async throws -> SyncFetchPage {
        try await require(session)
        if needsFullReconciliation && token == nil {
            try await persistence.clearEngineState(for: session.fingerprint)
            await discardEngine()
            guard account.matches(session) else {
                throw SyncTransportError.accountChanged
            }
            engine = try runtime.makeEngine(nil, self)
            needsFullReconciliation = false
        }
        guard let activeEngine = engine else { throw SyncTransportError.retryable }
        try Task.checkCancellation()
        eventError = nil
        let operationRuntime = runtime
        do {
            try await withTaskCancellationHandler {
                try await operationRuntime.fetch(activeEngine)
            } onCancel: {
                Task { await operationRuntime.cancel(activeEngine) }
            }
        }
        catch {
            if Task.isCancelled {
                await discardEngine()
                throw CancellationError()
            }
            let mapped = CloudKitErrorMapper.map(error)
            if mapped == .tokenExpired { needsFullReconciliation = true }
            throw mapped
        }
        if Task.isCancelled {
            await discardEngine()
            throw CancellationError()
        }
        try await require(session)
        if let eventError {
            if eventError == .tokenExpired { needsFullReconciliation = true }
            if eventError == .accountChanged { await retireEngine() }
            else { await discardEngine() }
            throw eventError
        }
        return try await persistence.page(after: token, for: session.fingerprint)
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard engine?.native === syncEngine else { return nil }
        let records = syncEngine.state.pendingRecordZoneChanges.compactMap { pending -> CKRecord? in
            guard case .saveRecord(let id) = pending, context.options.scope.contains(pending) else { return nil }
            return outgoing[id]
        }.prefix(200)
        guard !records.isEmpty else { return nil }
        return CKSyncEngine.RecordZoneChangeBatch(recordsToSave: Array(records))
    }

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard let activeEngine = engine, activeEngine.native === syncEngine else { return }
        guard account.fingerprint != nil else { return }
        switch event {
        case .stateUpdate(let update):
            do {
                await recordEngineState(try CloudKitEngineStateCodec.encode(update.stateSerialization), from: activeEngine.id)
            } catch {
                guard engine?.id == activeEngine.id else { return }
                eventError = .accountChanged
            }
        case .accountChange:
            let prior = engine
            account.invalidate()
            engine = nil
            needsFullReconciliation = false
            eventError = .accountChanged
            // Do not await cancellation inside an engine delegate callback.
            if let prior { Task { await runtime.cancel(prior) } }
        case .fetchedRecordZoneChanges(let fetched):
            await recordFetched(records: fetched.modifications.map(\.record),
                                hasDeletions: !fetched.deletions.isEmpty, from: activeEngine.id)
        case .fetchedDatabaseChanges(let fetched):
            if fetched.deletions.contains(where: { $0.zoneID == CloudRecordMapper.zoneID }) {
                eventError = .zoneReset
            }
        case .sentRecordZoneChanges(let sent):
            await recordSends(
                savedRecords: sent.savedRecords,
                failed: sent.failedRecordSaves.map { CloudKitRecordSaveFailure(record: $0.record, error: $0.error) },
                from: activeEngine.id
            )
        case .sentDatabaseChanges(let sent):
            if let failed = sent.failedZoneSaves.first { eventError = CloudKitErrorMapper.map(failed.error) }
        case .didFetchRecordZoneChanges(let fetched):
            if let error = fetched.error { eventError = CloudKitErrorMapper.map(error) }
        default: break
        }
    }

    /// Shared by the native delegate and deterministic adapter tests.
    func recordEngineState(_ serialized: Data, from engineID: UUID) async {
        guard engine?.id == engineID, let activeFingerprint = account.fingerprint else { return }
        let eventGeneration = account.generation
        // A rejected record or zone change must not make its CloudKit
        // change token durable. Recreate from the prior encrypted state.
        guard eventError == nil else { return }
        do {
            try await persistence.saveEngineState(serialized, for: activeFingerprint)
        } catch {
            guard engine?.id == engineID, account.generation == eventGeneration else { return }
            eventError = .accountChanged
        }
    }

    /// Shared by the native delegate and deterministic adapter tests.
    func recordFetched(records: [CKRecord], hasDeletions: Bool, from engineID: UUID) async {
        guard engine?.id == engineID, let activeFingerprint = account.fingerprint else { return }
        let eventGeneration = account.generation
        do {
            guard !hasDeletions else { eventError = .zoneReset; return }
            let changes = try records
                .filter { $0.recordID.zoneID == CloudRecordMapper.zoneID }
                .map { try CloudRecordMapper.change(from: $0) }
            try await persistence.append(changes, for: activeFingerprint)
        } catch {
            guard engine?.id == engineID, account.generation == eventGeneration else { return }
            eventError = .permission
        }
    }

    /// Shared by the native delegate and deterministic adapter tests.
    func recordSends(savedRecords: [CKRecord], failed: [CloudKitRecordSaveFailure], from engineID: UUID) async {
        guard let activeEngine = engine, activeEngine.id == engineID,
              let activeFingerprint = account.fingerprint else { return }
        let eventGeneration = account.generation
        acknowledged.append(contentsOf: savedRecords.compactMap { record in
            outgoing[record.recordID] == nil ? nil : record.recordID.recordName
        })
        for item in failed {
            guard engine?.id == engineID, account.generation == eventGeneration else { return }
            guard outgoing[item.record.recordID] != nil else { continue }
            let id = item.record.recordID.recordName
            failures[id] = CloudKitErrorMapper.map(item.error)
            if item.error.code == .serverRecordChanged, let server = item.error.serverRecord {
                do {
                    let remote = try CloudRecordMapper.change(from: server)
                    try await persistence.append([remote], for: activeFingerprint)
                    guard engine?.id == engineID, account.generation == eventGeneration else { return }
                    serverConflicts[id] = remote
                } catch {
                    guard engine?.id == engineID, account.generation == eventGeneration else { return }
                    eventError = .permission
                }
            }
            activeEngine.native?.state.remove(pendingRecordZoneChanges: [.saveRecord(item.record.recordID)])
        }
    }

    private func require(_ session: SyncAccountSession) async throws {
        guard case .available(let observed) = await accountState(),
              observed == session.fingerprint, account.matches(session) else {
            throw SyncTransportError.accountChanged
        }
    }

    private func retireEngine() async {
        account.rotateGeneration()
        await discardEngine()
    }

    private func discardEngine() async {
        let prior = engine
        engine = nil
        if let prior { await runtime.cancel(prior) }
    }

    private static func approvedContainer(for bundleIdentifier: String) -> String? {
        switch bundleIdentifier {
        case "com.taisa.app.dev": return "iCloud.com.taisa.app.dev"
        case "com.taisa.app": return "iCloud.com.taisa.app"
        default: return nil
        }
    }
}
