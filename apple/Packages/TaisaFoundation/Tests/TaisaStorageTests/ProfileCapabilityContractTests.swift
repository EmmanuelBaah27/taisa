import Foundation
import GRDB
import Testing
@testable import TaisaStorage

@Suite(.serialized) struct ProfileCapabilityContractTests {
    @Test func capabilityChoicesAreTypedEvidenceBackedAndReversible() async throws {
        let fixture = try await YouStorageFixture()
        defer { fixture.remove() }

        await #expect(throws: YouContractError.promotionEvidenceRequired) {
            try await fixture.capabilities.set(.seniorSelf, to: .trial, evidence: "  ", context: fixture.context(10))
        }

        let trial = try await fixture.capabilities.set(.seniorSelf, to: .trial, evidence: "Reviewed bounded coaching data", context: fixture.context(20))
        #expect(trial.state == .trial)
        #expect(trial.decisionSource == .user)
        #expect(trial.transportSource == .direct)

        let learning = try await fixture.capabilities.set(.seniorSelf, to: .learning, evidence: nil, context: fixture.context(30))
        #expect(learning.state == .learning)
        #expect(try await fixture.capabilities.get(.seniorSelf) == learning)
    }

    @Test func replayIsIdempotentWhileStaleAndCollidingDecisionsFailClosed() async throws {
        let fixture = try await YouStorageFixture()
        defer { fixture.remove() }
        let context = fixture.context(20)

        let first = try await fixture.capabilities.set(.voice, to: .ready, evidence: "Microphone flow verified", context: context)
        let replay = try await fixture.capabilities.set(.voice, to: .ready, evidence: "Microphone flow verified", context: context)
        #expect(replay == first)

        await #expect(throws: YouContractError.decisionCollision) {
            try await fixture.capabilities.set(.voice, to: .trusted, evidence: "Different decision", context: context)
        }
        await #expect(throws: YouContractError.staleDecision) {
            try await fixture.capabilities.set(.voice, to: .learning, evidence: nil, context: fixture.context(19))
        }
    }

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
    let capabilities: CapabilityCommandRepository
    let profile: ProfileCommandRepository
    let profileID = UUID().uuidString
    let deviceID = UUID().uuidString

    init() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: YouStorageKeys())
        capabilities = CapabilityCommandRepository(store: store)
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
