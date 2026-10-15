import Foundation
import Testing
@testable import TaisaStorage

@Suite(.serialized) struct ProfileContractTests {
    @Test func profileCommandsTrimApprovedFieldsAndRejectOversizedInputAtomically() async throws {
        let fixture = try await YouStorageFixture()
        defer { fixture.remove() }

        let saved = try await fixture.profile.save(
            id: fixture.profileID,
            displayName: "  Baah  ",
            headline: "  Product builder  ",
            biography: "  Building Taisa.  ",
            context: fixture.context(10)
        )
        #expect(saved.displayName == "Baah")
        #expect(saved.headline == "Product builder")
        #expect(saved.biography == "Building Taisa.")

        await #expect(throws: YouContractError.invalidProfile) {
            try await fixture.profile.save(
                id: fixture.profileID,
                displayName: String(repeating: "x", count: 81),
                headline: "Changed",
                biography: "Changed",
                context: fixture.context(20)
            )
        }
        #expect(try await fixture.profile.get(id: fixture.profileID) == saved)
    }

    @Test func publicErrorsRemainContentFree() {
        let privateCanaries = ["secret-token", "/private/store.sqlite", "private biography"]
        for error in YouContractError.allCases {
            let rendered = String(describing: error)
            #expect(privateCanaries.allSatisfy { !rendered.contains($0) })
        }
    }
}

private struct YouStorageFixture {
    let directory: URL
    let store: TaisaStore
    let profile: ProfileCommandRepository
    let profileID = UUID().uuidString
    let deviceID = UUID().uuidString

    init() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: YouStorageKeys())
        profile = ProfileCommandRepository(store: store)
    }

    func context(_ timestamp: Int64) -> MutationContext {
        .init(id: UUID().uuidString, deviceID: deviceID, timestamp: timestamp)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private actor YouStorageKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}
