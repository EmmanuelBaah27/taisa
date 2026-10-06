import CloudKit
import CryptoKit
import Foundation
import TaisaStorage
import TaisaSync

/// A private-database CKSyncEngine adapter. The coordinator sees only sealed
/// `EncryptedChange` values and SQLCipher-backed transport tokens.
public actor CloudKitSyncTransport: SyncTransport, CKSyncEngineDelegate {
    private let container: CKContainer
    private let persistence: SyncTransportPersistence
    private let assetRoot: URL
    private var engine: CKSyncEngine?
    private var fingerprint: Data?
    private var generation = UUID()
    private var outgoing: [CKRecord.ID: CKRecord] = [:]
    private var acknowledged: [String] = []
    private var failures: [String: SyncTransportError] = [:]
    private var serverConflicts: [String: EncryptedChange] = [:]
    private var eventError: SyncTransportError?
    private var needsFullReconciliation = false

    public init(containerIdentifier: String, bundleIdentifier: String, store: TaisaStore) throws {
        let approved: String?
        switch bundleIdentifier {
        case "com.taisa.app.dev": approved = "iCloud.com.taisa.app.dev"
        case "com.taisa.app": approved = "iCloud.com.taisa.app"
        default: approved = nil
        }
        guard approved == containerIdentifier else { throw SyncTransportError.permission }
        container = CKContainer(identifier: containerIdentifier)
        persistence = SyncTransportPersistence(store: store)
        assetRoot = FileManager.default.temporaryDirectory.appendingPathComponent("taisa-cloudkit-\(UUID().uuidString)")
    }

    public func accountState() async -> SyncAccountState {
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                let user = try await container.userRecordID()
                let observed = Data(SHA256.hash(data: Data(user.recordName.utf8)))
                if let fingerprint, fingerprint != observed {
                    generation = UUID()
                    engine = nil
                    needsFullReconciliation = false
                }
                fingerprint = observed
                return .available(fingerprint: observed)
            case .noAccount:
                if fingerprint != nil { generation = UUID(); engine = nil }
                fingerprint = nil
                needsFullReconciliation = false
                return .noAccount
            default:
                return .unavailable
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
            let serialized = try await persistence.engineState(for: observed)
            engine = try makeEngine(serialized: serialized)
        }
        return SyncAccountSession(fingerprint: observed, generation: generation)
    }

    public func send(_ changes: [EncryptedChange], session: SyncAccountSession) async throws -> SyncSendResult {
        try await require(session)
        guard changes.count <= 200 else { throw SyncTransportError.permission }
        guard let activeEngine = engine else { throw SyncTransportError.retryable }
        try Task.checkCancellation()
        acknowledged = []
        failures = [:]
        serverConflicts = [:]
        eventError = nil
        defer {
            outgoing = [:]
            try? FileManager.default.removeItem(at: assetRoot)
        }
        for change in changes {
            let record = try CloudRecordMapper.makeRecord(change, assetDirectory: assetRoot)
            outgoing[record.recordID] = record
        }
        let zone = CKRecordZone(zoneID: CloudRecordMapper.zoneID)
        activeEngine.state.add(pendingDatabaseChanges: [.saveZone(zone)])
        activeEngine.state.add(pendingRecordZoneChanges: outgoing.keys.map { .saveRecord($0) })
        do { try await activeEngine.sendChanges() }
        catch {
            let mapped = CloudKitErrorMapper.map(error)
            guard mapped != .accountChanged, !acknowledged.isEmpty || !failures.isEmpty else { throw mapped }
            let known = Set(acknowledged).union(failures.keys)
            for change in changes where !known.contains(change.id) { failures[change.id] = mapped }
        }
        try await require(session)
        if let eventError {
            engine = nil
            throw eventError
        }
        return SyncSendResult(acknowledgedIDs: acknowledged, failures: failures, serverConflicts: serverConflicts)
    }

    public func fetch(after token: Data?, session: SyncAccountSession) async throws -> SyncFetchPage {
        try await require(session)
        if needsFullReconciliation && token == nil {
            try await persistence.clearEngineState(for: session.fingerprint)
            engine = try makeEngine(serialized: nil)
            needsFullReconciliation = false
        }
        guard let activeEngine = engine else { throw SyncTransportError.retryable }
        try Task.checkCancellation()
        eventError = nil
        do { try await activeEngine.fetchChanges() }
        catch {
            let mapped = CloudKitErrorMapper.map(error)
            if mapped == .tokenExpired { needsFullReconciliation = true }
            throw mapped
        }
        try await require(session)
        if let eventError {
            if eventError == .tokenExpired { needsFullReconciliation = true }
            engine = nil
            throw eventError
        }
        return try await persistence.page(after: token, for: session.fingerprint)
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let records = syncEngine.state.pendingRecordZoneChanges.compactMap { pending -> CKRecord? in
            guard case .saveRecord(let id) = pending, context.options.scope.contains(pending) else { return nil }
            return outgoing[id]
        }.prefix(200)
        guard !records.isEmpty else { return nil }
        return CKSyncEngine.RecordZoneChangeBatch(recordsToSave: Array(records))
    }

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard let activeFingerprint = fingerprint else { return }
        switch event {
        case .stateUpdate(let update):
            // A rejected record or zone change must not make its CloudKit
            // change token durable. Recreate from the prior encrypted state.
            guard eventError == nil else { return }
            do {
                try await persistence.saveEngineState(CloudKitEngineStateCodec.encode(update.stateSerialization), for: activeFingerprint)
            } catch { eventError = .accountChanged }
        case .accountChange:
            generation = UUID()
            engine = nil
            fingerprint = nil
            needsFullReconciliation = false
            eventError = .accountChanged
        case .fetchedRecordZoneChanges(let fetched):
            do {
                guard fetched.deletions.isEmpty else { eventError = .zoneReset; return }
                let changes = try fetched.modifications
                    .filter { $0.record.recordID.zoneID == CloudRecordMapper.zoneID }
                    .map { try CloudRecordMapper.change(from: $0.record) }
                try await persistence.append(changes, for: activeFingerprint)
            } catch { eventError = .permission }
        case .fetchedDatabaseChanges(let fetched):
            if fetched.deletions.contains(where: { $0.zoneID == CloudRecordMapper.zoneID }) {
                eventError = .zoneReset
            }
        case .sentRecordZoneChanges(let sent):
            acknowledged.append(contentsOf: sent.savedRecords.map { $0.recordID.recordName })
            for failed in sent.failedRecordSaves {
                let id = failed.record.recordID.recordName
                failures[id] = CloudKitErrorMapper.map(failed.error)
                if failed.error.code == .serverRecordChanged, let server = failed.error.serverRecord {
                    do {
                        let remote = try CloudRecordMapper.change(from: server)
                        try await persistence.append([remote], for: activeFingerprint)
                        serverConflicts[id] = remote
                    }
                    catch { eventError = .permission }
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
              observed == session.fingerprint, generation == session.generation else {
            throw SyncTransportError.accountChanged
        }
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
