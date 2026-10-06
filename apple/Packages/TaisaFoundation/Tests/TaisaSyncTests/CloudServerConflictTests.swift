import Foundation
import Testing
import TaisaSecurity
import TaisaStorage
import TaisaSync

private actor ConflictKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}

private actor EquivalentServerConflictTransport: SyncTransport {
    let fingerprint: Data
    let vault: Vault
    let divergent: Bool
    private var server: EncryptedChange?
    private let generation = UUID()

    init(fingerprint: Data, vault: Vault, divergent: Bool = false) {
        self.fingerprint = fingerprint; self.vault = vault; self.divergent = divergent
    }
    func accountState() async -> SyncAccountState { .available(fingerprint: fingerprint) }
    func bind(expectedFingerprint: Data) async throws -> SyncAccountSession {
        guard expectedFingerprint == fingerprint else { throw SyncTransportError.accountChanged }
        return SyncAccountSession(fingerprint: fingerprint, generation: generation)
    }
    func send(_ changes: [EncryptedChange], session: SyncAccountSession) async throws -> SyncSendResult {
        guard session.generation == generation, let first = changes.first else { throw SyncTransportError.accountChanged }
        var plaintext = try vault.open(first.envelope)
        if divergent {
            var object = try JSONSerialization.jsonObject(with: plaintext) as! [String: Any]
            var record = object["record"] as! [String: Any]
            record["displayName"] = "Different private name"
            object["record"] = record
            plaintext = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        }
        let equivalent = EncryptedChange(id: first.id, envelope: try vault.seal(plaintext, metadata: first.envelope.metadata))
        server = equivalent
        return SyncSendResult(acknowledgedIDs: [], failures: [first.id: .retryable], serverConflicts: [first.id: equivalent])
    }
    func fetch(after token: Data?, session: SyncAccountSession) async throws -> SyncFetchPage {
        guard session.generation == generation else { throw SyncTransportError.accountChanged }
        return SyncFetchPage(changes: server.map { [$0] } ?? [], token: Data("1".utf8))
    }
}

@Suite struct CloudServerConflictTests {
    @Test func equivalentEncryptedServerVersionAcknowledgesReplay() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: ConflictKeys())
        let vault = try Vault.generate()
        let id = UUID().uuidString
        try await ProfileRepository(store: store).create(
            ProfileRecord(id: id, displayName: "Private name", headline: "", biography: "", updatedAtMS: 10),
            context: MutationContext(id: UUID().uuidString, deviceID: UUID().uuidString, timestamp: 10)
        )
        let transport = EquivalentServerConflictTransport(fingerprint: Data("account".utf8), vault: vault)
        let outcome = await SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual)
        #expect(outcome.state == .upToDate)
        #expect(try await ChangeJournal(store: store).pending(limit: 10).isEmpty)
    }

    @Test func divergentServerVersionNeverAcknowledgesLocalOutbox() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: ConflictKeys())
        let vault = try Vault.generate()
        let mutationID = UUID().uuidString
        try await ProfileRepository(store: store).create(
            ProfileRecord(id: UUID().uuidString, displayName: "Original private name", headline: "", biography: "", updatedAtMS: 10),
            context: MutationContext(id: mutationID, deviceID: UUID().uuidString, timestamp: 10)
        )
        let transport = EquivalentServerConflictTransport(fingerprint: Data("account".utf8), vault: vault, divergent: true)
        let outcome = await SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual)
        #expect(outcome.state != .upToDate)
        #expect(try await ChangeJournal(store: store).pending(limit: 10).map(\.id) == [mutationID])
    }
}
