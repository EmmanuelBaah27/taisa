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

@Suite struct SyncTransportPersistenceTests {
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
