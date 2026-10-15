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

    @Test func loadPreservesTypedStorageFailures() async throws {
        let fixture = try await YouQueryFixture()
        defer { fixture.remove() }
        try await TaisaStore.withExclusiveReplacement(at: fixture.storeURL) {}

        do {
            _ = try await YouQuery(store: fixture.store).load()
            Issue.record("A closed store must surface its typed storage failure")
        } catch let error as StorageError {
            #expect(error == .openFailed)
        } catch {
            Issue.record("Expected StorageError.openFailed, got \(error)")
        }
    }

    @Test func loadRefreshesOperationalFactsForEverySnapshot() async throws {
        let fixture = try await YouQueryFixture()
        defer { fixture.remove() }
        let facts = OperationalFactsSequence()
        let query = YouQuery(store: fixture.store, operational: { await facts.next() })

        #expect(try await query.load().diagnostics.microphone == .denied)
        #expect(try await query.load().diagnostics.microphone == .granted)
    }
}

private actor OperationalFactsSequence {
    private var count = 0
    func next() -> YouOperationalFacts {
        count += 1
        return .init(
            store: .healthy,
            recovery: .unknown,
            microphone: count == 1 ? .denied : .granted,
            gateway: .unknown,
            appProtection: .unknown
        )
    }
}

private struct YouQueryFixture {
    let directory: URL
    let storeURL: URL
    let store: TaisaStore
    let profileID = UUID().uuidString
    let deviceID = UUID().uuidString

    init() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appendingPathComponent("store.sqlite")
        store = try await TaisaStore.open(at: storeURL, keyStore: YouQueryKeys())
    }
    func context(_ timestamp: Int64) -> MutationContext { .init(id: UUID().uuidString, deviceID: deviceID, timestamp: timestamp) }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private actor YouQueryKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}
