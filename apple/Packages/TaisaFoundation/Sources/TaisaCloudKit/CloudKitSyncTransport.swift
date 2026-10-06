import CloudKit
import CryptoKit
import Foundation
import TaisaStorage
import TaisaSync

struct CloudKitTransportRuntime: Sendable {
    let accountState: @Sendable (CKContainer) async throws -> SyncAccountState
    let send: @Sendable (CKSyncEngine) async throws -> Void
    let fetch: @Sendable (CKSyncEngine) async throws -> Void
    let cancel: @Sendable (CKSyncEngine) async -> Void

    static let live = Self(
        accountState: { container in
            switch try await container.accountStatus() {
            case .available:
                let user = try await container.userRecordID()
                return .available(fingerprint: Data(SHA256.hash(data: Data(user.recordName.utf8))))
            case .noAccount: return .noAccount
            default: return .unavailable
            }
        },
        send: { try await $0.sendChanges() },
        fetch: { try await $0.fetchChanges() },
        cancel: { await $0.cancelOperations() }
    )
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
    private let container: CKContainer
    private let persistence: SyncTransportPersistence
    private let assetRoot: URL
    private let runtime: CloudKitTransportRuntime
    private let operationIsolation = CloudKitOperationIsolation()
    private var engine: CKSyncEngine?
    private var account = CloudKitAccountBinding()
    private var outgoing: [CKRecord.ID: CKRecord] = [:]
    private var acknowledged: [String] = []
    private var failures: [String: SyncTransportError] = [:]
    private var serverConflicts: [String: EncryptedChange] = [:]
    private var eventError: SyncTransportError?
    private var needsFullReconciliation = false

    public init(containerIdentifier: String, bundleIdentifier: String, store: TaisaStore) throws {
        try self.init(containerIdentifier: containerIdentifier, bundleIdentifier: bundleIdentifier, store: store, runtime: .live)
    }

    init(containerIdentifier: String, bundleIdentifier: String, store: TaisaStore,
         runtime: CloudKitTransportRuntime, assetRoot: URL? = nil) throws {
        let approved: String?
        switch bundleIdentifier {
        case "com.taisa.app.dev": approved = "iCloud.com.taisa.app.dev"
        case "com.taisa.app": approved = "iCloud.com.taisa.app"
        default: approved = nil
        }
        guard approved == containerIdentifier else { throw SyncTransportError.permission }
        container = CKContainer(identifier: containerIdentifier)
        persistence = SyncTransportPersistence(store: store)
        self.runtime = runtime
        self.assetRoot = assetRoot ?? FileManager.default.temporaryDirectory.appendingPathComponent("taisa-cloudkit-\(UUID().uuidString)")
    }

    public func accountState() async -> SyncAccountState {
        do {
            let state = try await runtime.accountState(container)
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
            if engine == nil { engine = try makeEngine(serialized: serialized) }
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
        let zone = CKRecordZone(zoneID: CloudRecordMapper.zoneID)
        activeEngine.state.add(pendingDatabaseChanges: [.saveZone(zone)])
        activeEngine.state.add(pendingRecordZoneChanges: outgoing.keys.map { .saveRecord($0) })
        let operationRuntime = runtime
        do {
            try await withTaskCancellationHandler {
                try await operationRuntime.send(activeEngine)
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
            engine = try makeEngine(serialized: nil)
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
        guard engine === syncEngine else { return nil }
        let records = syncEngine.state.pendingRecordZoneChanges.compactMap { pending -> CKRecord? in
            guard case .saveRecord(let id) = pending, context.options.scope.contains(pending) else { return nil }
            return outgoing[id]
        }.prefix(200)
        guard !records.isEmpty else { return nil }
        return CKSyncEngine.RecordZoneChangeBatch(recordsToSave: Array(records))
    }

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard engine === syncEngine else { return }
        guard let activeFingerprint = account.fingerprint else { return }
        let eventGeneration = account.generation
        switch event {
        case .stateUpdate(let update):
            // A rejected record or zone change must not make its CloudKit
            // change token durable. Recreate from the prior encrypted state.
            guard eventError == nil else { return }
            do {
                try await persistence.saveEngineState(CloudKitEngineStateCodec.encode(update.stateSerialization), for: activeFingerprint)
            } catch {
                guard engine === syncEngine, account.generation == eventGeneration else { return }
                eventError = .accountChanged
            }
        case .accountChange:
            account.invalidate()
            engine = nil
            needsFullReconciliation = false
            eventError = .accountChanged
            // Do not await cancellation inside an engine delegate callback.
            Task { await runtime.cancel(syncEngine) }
        case .fetchedRecordZoneChanges(let fetched):
            do {
                guard fetched.deletions.isEmpty else { eventError = .zoneReset; return }
                let changes = try fetched.modifications
                    .filter { $0.record.recordID.zoneID == CloudRecordMapper.zoneID }
                    .map { try CloudRecordMapper.change(from: $0.record) }
                try await persistence.append(changes, for: activeFingerprint)
            } catch {
                guard engine === syncEngine, account.generation == eventGeneration else { return }
                eventError = .permission
            }
        case .fetchedDatabaseChanges(let fetched):
            if fetched.deletions.contains(where: { $0.zoneID == CloudRecordMapper.zoneID }) {
                eventError = .zoneReset
            }
        case .sentRecordZoneChanges(let sent):
            acknowledged.append(contentsOf: sent.savedRecords.compactMap { record in
                outgoing[record.recordID] == nil ? nil : record.recordID.recordName
            })
            for failed in sent.failedRecordSaves {
                guard engine === syncEngine, account.generation == eventGeneration else { return }
                guard outgoing[failed.record.recordID] != nil else { continue }
                let id = failed.record.recordID.recordName
                failures[id] = CloudKitErrorMapper.map(failed.error)
                if failed.error.code == .serverRecordChanged, let server = failed.error.serverRecord {
                    do {
                        let remote = try CloudRecordMapper.change(from: server)
                        try await persistence.append([remote], for: activeFingerprint)
                        guard engine === syncEngine, account.generation == eventGeneration else { return }
                        serverConflicts[id] = remote
                    }
                    catch {
                        guard engine === syncEngine, account.generation == eventGeneration else { return }
                        eventError = .permission
                    }
                }
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(failed.record.recordID)])
            }
        case .sentDatabaseChanges(let sent):
            if let failed = sent.failedZoneSaves.first { eventError = CloudKitErrorMapper.map(failed.error) }
        case .didFetchRecordZoneChanges(let fetched):
            if let error = fetched.error { eventError = CloudKitErrorMapper.map(error) }
        default: break
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

    private func makeEngine(serialized: Data?) throws -> CKSyncEngine {
        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: try CloudKitEngineStateCodec.decode(serialized),
            delegate: self
        )
        configuration.automaticallySync = false
        configuration.subscriptionID = "TaisaVaultV1Changes"
        return CKSyncEngine(configuration)
    }
}
