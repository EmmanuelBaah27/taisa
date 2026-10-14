import Foundation
import Testing
@testable import TaisaStorage

@Suite(.serialized) struct YouQueryTests {
    @Test func loadReturnsOneOfflineSnapshotWithHonestDefaults() async throws {
        let fixture = try await YouQueryFixture()
        defer { fixture.remove() }
        _ = try await ProfileCommandRepository(store: fixture.store).save(
            id: fixture.profileID, displayName: "Baah", headline: "Builder", biography: "Local",
            context: fixture.context(10)
        )
        _ = try await CapabilityCommandRepository(store: fixture.store).set(
            .voice, to: .trial, evidence: "Reviewed microphone boundary", context: fixture.context(20)
        )

        let snapshot = try await YouQuery(
            store: fixture.store,
            operational: .init(
                store: .healthy,
                recovery: .ready,
                microphone: .denied,
                gateway: .unavailable,
                appProtection: .enabled
            )
        ).load()

        #expect(snapshot.profile?.displayName == "Baah")
        #expect(snapshot.capabilities.first(where: { $0.id == .voice })?.chosenState == .trial)
        #expect(snapshot.capabilities.first(where: { $0.id == .voice })?.availability == .unavailable)
        #expect(snapshot.capabilities.first(where: { $0.id == .insights })?.chosenState == .learning)
        #expect(snapshot.diagnostics.store == .healthy)
    }

    @Test func snapshotTypesCannotCarrySecretsPathsOrPrivateContent() {
        let facts = YouOperationalFacts(
            store: .unknown,
            recovery: .unknown,
            microphone: .notDetermined,
            gateway: .unknown,
            appProtection: .unknown
        )
        let reflected = String(reflecting: facts)
        for canary in ["bearer-token", "/private/store.sqlite", "private transcript"] {
            #expect(!reflected.contains(canary))
        }
    }
}

private struct YouQueryFixture {
    let directory: URL
    let store: TaisaStore
    let profileID = UUID().uuidString
    let deviceID = UUID().uuidString

    init() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: YouQueryKeys())
    }
    func context(_ timestamp: Int64) -> MutationContext { .init(id: UUID().uuidString, deviceID: deviceID, timestamp: timestamp) }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private actor YouQueryKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}
