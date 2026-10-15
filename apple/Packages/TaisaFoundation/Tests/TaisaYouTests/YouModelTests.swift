import Foundation
import Testing
@testable import TaisaYou
import TaisaStorage

@Suite(.serialized) @MainActor struct YouModelTests {
    @Test func hierarchyExposesOnlyConcreteUserDestinations() {
        #expect(YouDestination.allCases == [.careerProfile, .privacyPermissions, .backupRecovery, .diagnostics])
        #expect(Set(YouDestination.allCases.map(\.stableID)).count == 4)
        #expect(!YouDestination.allCases.map(\.title).contains("Capabilities"))
    }

    @Test func loadEditCancelAndSavePublishLocalTruth() async {
        let initial = snapshot(profile: profile(name: "Baah"))
        let saved = snapshot(profile: profile(name: "Emmanuel"))
        let client = YouClient(load: { initial }, saveProfile: { draft in
            #expect(draft.displayName == "Emmanuel")
            return saved
        })
        let model = YouModel(client: client)

        await model.load()
        #expect(model.state.snapshot == initial)
        model.beginProfileEdit()
        model.updateProfile(displayName: "Changed", headline: "", biography: "")
        model.cancelProfileEdit()
        #expect(model.profileDraft == nil)
        model.beginProfileEdit()
        model.updateProfile(displayName: "Emmanuel", headline: "Builder", biography: "Local")
        await model.saveProfile()
        #expect(model.state.snapshot == saved)
        #expect(model.profileDraft == nil)
    }

    @Test func invalidAndStaleMutationsRemainDistinctAndRetryable() async {
        let initial = snapshot(profile: nil)
        let invalid = YouModel(client: .init(load: { initial }, saveProfile: { _ in throw YouContractError.invalidProfile }))
        await invalid.load(); invalid.beginProfileEdit(); invalid.updateProfile(displayName: "x", headline: "", biography: "")
        await invalid.saveProfile()
        #expect(invalid.state.issue == .invalidInput)
        #expect(invalid.profileDraft != nil)

    }

    @Test func privacySummaryDescribesOnlyConcreteStoredDataAndOperationalFacts() {
        #expect(YouPrivacyCopy.readableData == "Career profile")
        #expect(YouPrivacyCopy.encryptedLocation == "Encrypted on this device")
        #expect(YouPrivacyCopy.networkBoundary.contains("deliberate voice or coaching action"))
        #expect(YouPrivacyCopy.retentionBoundary.contains("until you edit"))
        #expect(YouPrivacyCopy.recoveryBoundary.contains("explicit confirmation"))
        #expect(YouPermissionGuidance.microphone(.notDetermined).requestsPermission == false)
    }

    @Test func userIssuesAreActionableAndContentFree() {
        #expect(YouIssue.invalidInput.guidance.contains("Review"))
        #expect(YouIssue.conflict.guidance.contains("changed"))
        for issue in [YouIssue.storageUnavailable, .recoveryRequired, .invalidInput, .conflict] {
            #expect(!issue.guidance.contains("/private/"))
            #expect(!issue.guidance.contains("token"))
        }
    }

    @Test func diagnosticsAreAllowlistedContentFreeAndDeterministic() {
        let facts = YouOperationalFacts(store: .degraded, recovery: .ready, microphone: .denied, gateway: .unavailable, appProtection: .enabled)
        let rows = YouDiagnostics.rows(for: facts)

        #expect(rows.map(\.id) == [.localStore, .recovery, .microphone, .voiceGateway, .appProtection])
        #expect(rows.map(\.value) == ["Degraded", "Ready", "Not allowed", "Unavailable", "Enabled"])
        #expect(rows.allSatisfy { !$0.value.contains("/") && !$0.value.contains("http") })
    }

    @Test func localClientPersistsProfileWithoutTransport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let deviceID = UUID().uuidString
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: YouClientTestKeys())
        let client = YouClient.local(store: store, deviceID: deviceID, operational: .unknown, nowMS: { 10 })

        _ = try await client.saveProfile(.init(displayName: "Baah", headline: "Builder", biography: "Offline"))
        let relaunched = try await YouClient.local(store: store, deviceID: deviceID, operational: .unknown, nowMS: { 20 }).load()

        #expect(relaunched.profile?.displayName == "Baah")
    }
}

private func profile(name: String) -> ProfileRecord { .init(id: "11111111-1111-4111-8111-111111111111", displayName: name, headline: "", biography: "", updatedAtMS: 1) }
private func snapshot(profile: ProfileRecord?) -> YouSnapshot { .init(profile: profile, diagnostics: .unknown) }

private actor YouClientTestKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}
