import Foundation
import GRDB
import Testing
import TaisaSecurity
import TaisaStorage
import TaisaSync

private actor PersistenceKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}

private actor InterruptedPersistedPages: SyncTransport {
    let fingerprint = Data("account-one".utf8)
    let generation = UUID()
    let persistence: SyncTransportPersistence
    var calls = 0
    let interruptSecond: Bool

    init(store: TaisaStore, interruptSecond: Bool = false) {
        persistence = SyncTransportPersistence(store: store)
        self.interruptSecond = interruptSecond
    }
    func accountState() async -> SyncAccountState { .available(fingerprint: fingerprint) }
    func bind(expectedFingerprint: Data) async throws -> SyncAccountSession {
        .init(fingerprint: fingerprint, generation: generation)
    }
    func send(_ changes: [EncryptedChange], session: SyncAccountSession) async throws -> SyncSendResult {
        .init(acknowledgedIDs: changes.map(\.id))
    }
    func fetch(after token: Data?, session: SyncAccountSession) async throws -> SyncFetchPage {
        calls += 1
        let page = try await persistence.page(after: token, for: fingerprint)
        if interruptSecond && calls == 2 { withUnsafeCurrentTask { $0?.cancel() } }
        return page
    }
}

@Suite struct SyncTransportPersistenceTests {
    @Test func interruptedDependentPageReplaysAfterCoordinatorRelaunch() async throws {
        func store() async throws -> (TaisaStore, URL) {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("taisa-paging-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return (try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: PersistenceKeys()), directory)
        }
        let (source, sourceDirectory) = try await store()
        let (target, targetDirectory) = try await store()
        defer {
            try? FileManager.default.removeItem(at: sourceDirectory)
            try? FileManager.default.removeItem(at: targetDirectory)
        }
        let vault = try Vault.generate()
        let conversationID = UUID().uuidString, messageID = UUID().uuidString
        let context = MutationContext(id: UUID().uuidString, deviceID: UUID().uuidString, timestamp: 10)
        let conversations = ConversationRepository(store: source)
        try await conversations.create(.init(id: conversationID, title: "Private chat", createdAtMS: 10, updatedAtMS: 10), context: context)
        try await conversations.createMessage(.init(id: messageID, conversationID: conversationID, role: "user", body: "Private message", createdAtMS: 10), context: .init(id: UUID().uuidString, deviceID: context.deviceID, timestamp: 10))
        try await ProfileRepository(store: source).create(.init(id: UUID().uuidString, displayName: "Filler", headline: "", biography: "", updatedAtMS: 10), context: .init(id: UUID().uuidString, deviceID: context.deviceID, timestamp: 10))
        let changes = try await ChangeJournal(store: source).pending(limit: 10).map {
            EncryptedChange(id: $0.id, envelope: try vault.seal($0.payload, metadata: .init(vaultID: vault.id, recordID: UUID(uuidString: $0.id)!, entityType: $0.entityType, schemaVersion: 1, tombstone: false)))
        }
        let parent = try #require(changes.first { $0.envelope.metadata.entityType == "conversation" })
        let child = try #require(changes.first { $0.envelope.metadata.entityType == "message" })
        let filler = try #require(changes.first { $0.envelope.metadata.entityType == "profile" })
        try await target.write { db in
            try db.execute(sql: "INSERT INTO sync_state (id, vault_id, account_fingerprint, engine_state, updated_at_ms) VALUES (1, ?, ?, ?, 0)", arguments: [vault.id.uuidString, Data("account-one".utf8), Data("{}".utf8)])
        }
        try await SyncTransportPersistence(store: target).append([child] + Array(repeating: filler, count: 199) + [parent], for: Data("account-one".utf8))
        let first = Task {
            await SyncCoordinator(store: target, vault: vault, transport: InterruptedPersistedPages(store: target, interruptSecond: true)).synchronize(reason: .manual)
        }
        let interrupted = await first.value
        #expect(interrupted.state == .retrying)
        let durable = try await target.read { try Data.fetchOne($0, sql: "SELECT change_token FROM sync_state WHERE id = 1") }
        #expect(durable == nil)
        let resumed = await SyncCoordinator(store: target, vault: vault, transport: InterruptedPersistedPages(store: target)).synchronize(reason: .manual)
        #expect(resumed.state == .upToDate)
        let count = try await target.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM messages WHERE id = ?", arguments: [messageID]) }
        #expect(count == 1)
    }

    @Test func requestedNextPageDoesNotPruneUnappliedEarlierPage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: PersistenceKeys())
        let fingerprint = Data("account-one".utf8)
        let vault = try Vault.generate()
        try await store.write { db in
            try db.execute(sql: "INSERT INTO sync_state (id, vault_id, account_fingerprint, engine_state, updated_at_ms) VALUES (1, ?, ?, ?, 0)", arguments: [vault.id.uuidString, fingerprint, Data("{}".utf8)])
        }
        let persistence = SyncTransportPersistence(store: store)
        let ids = [UUID(), UUID()]
        let changes = try ids.map { id in
            EncryptedChange(id: id.uuidString, envelope: try vault.seal(Data(id.uuidString.utf8), metadata: .init(vaultID: vault.id, recordID: id, entityType: "profile", schemaVersion: 1, tombstone: false)))
        }
        try await persistence.append(changes, for: fingerprint)
        let first = try await persistence.page(after: nil, for: fingerprint, limit: 1)
        #expect(first.changes == [changes[0]])
        let second = try await persistence.page(after: first.token, for: fingerprint, limit: 1)
        #expect(second.changes == [changes[1]])
        let durable = try await store.read { try Data.fetchOne($0, sql: "SELECT change_token FROM sync_state WHERE id = 1") }
        #expect(durable == nil)
        let relaunched = try await SyncTransportPersistence(store: store).page(after: nil, for: fingerprint)
        #expect(relaunched.changes == changes)
        try await store.write { db in
            try db.execute(sql: "UPDATE sync_state SET change_token = ? WHERE id = 1", arguments: [first.token])
        }
        let afterCommit = try await persistence.page(after: nil, for: fingerprint)
        #expect(afterCommit.changes == [changes[1]])
        #expect(afterCommit.token == second.token)
        try await store.write { db in
            try db.execute(sql: "UPDATE sync_state SET change_token = ? WHERE id = 1", arguments: [second.token])
        }
        let staleRequest = try await persistence.page(after: nil, for: fingerprint)
        #expect(staleRequest.changes.isEmpty)
        #expect(staleRequest.token == second.token)
    }

    @Test func fetchedCiphertextSurvivesCoordinatorCheckpointRewriteUntilCommitted() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: PersistenceKeys())
        let fingerprint = Data("account-one".utf8)
        let vault = try Vault.generate()
        try await store.write { db in
            try db.execute(sql: "INSERT INTO sync_state (id, vault_id, account_fingerprint, engine_state, updated_at_ms) VALUES (1, ?, ?, ?, 0)", arguments: [vault.id.uuidString, fingerprint, Data("{}".utf8)])
        }
        let persistence = SyncTransportPersistence(store: store)
        let state = Data("opaque-CKSyncEngine-serialization".utf8)
        try await persistence.saveEngineState(state, for: fingerprint)
        let id = UUID()
        let change = EncryptedChange(id: id.uuidString, envelope: VaultEnvelope(version: 1, metadata: EnvelopeMetadata(vaultID: vault.id, recordID: id, entityType: "message", schemaVersion: 1, tombstone: false), ciphertext: Data(repeating: 7, count: 32)))
        try await persistence.append([change], for: fingerprint)
        let first = try await persistence.page(after: nil, for: fingerprint)
        #expect(first.changes == [change])
        let fake = InMemorySyncTransport(accountFingerprint: fingerprint)
        _ = await SyncCoordinator(store: store, vault: vault, transport: fake).synchronize(reason: .manual)
        #expect(try await persistence.engineState(for: fingerprint) == state)
        let replay = try await persistence.page(after: nil, for: fingerprint)
        #expect(replay.changes == [change])
        try await persistence.clearEngineState(for: fingerprint)
        #expect(try await persistence.engineState(for: fingerprint) == nil)
        #expect(try await persistence.page(after: nil, for: fingerprint).changes == [change])
        let committed = try await persistence.page(after: first.token, for: fingerprint)
        #expect(committed.changes.isEmpty)
    }
}
