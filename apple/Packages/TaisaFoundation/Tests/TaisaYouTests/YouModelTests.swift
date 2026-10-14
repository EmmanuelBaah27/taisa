import Testing
@testable import TaisaYou
import TaisaStorage

@Suite(.serialized) @MainActor struct YouModelTests {
    @Test func hierarchyOwnsFiveStableUserDestinations() {
        #expect(YouDestination.allCases == [.careerProfile, .capabilities, .privacyPermissions, .backupRecovery, .diagnostics])
        #expect(Set(YouDestination.allCases.map(\.stableID)).count == 5)
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

        let stale = YouModel(client: .init(load: { initial }, setCapability: { _, _ in throw YouContractError.staleDecision }))
        await stale.load(); await stale.setCapability(.voice, to: .trusted)
        #expect(stale.state.issue == .conflict)
    }

    @Test func promotionRequiresReviewWhileDemotionAppliesImmediately() async {
        let current = CapabilityOverview(id: .voice, chosenState: .learning, availability: .limited, decidedAtMS: nil)
        let initial = snapshot(profile: nil, capabilities: [current])
        let promoted = snapshot(profile: nil, capabilities: [.init(id: .voice, chosenState: .trusted, availability: .limited, decidedAtMS: 2)])
        let demoted = snapshot(profile: nil, capabilities: [.init(id: .voice, chosenState: .learning, availability: .limited, decidedAtMS: 3)])
        let client = YouClient(load: { initial }, setCapability: { _, state in state == .trusted ? promoted : demoted })
        let model = YouModel(client: client)

        await model.load()
        await model.requestCapabilityChange(.voice, to: .trusted)
        #expect(model.pendingCapabilityReview == .init(id: .voice, from: .learning, to: .trusted))
        #expect(model.state.snapshot == initial)
        await model.confirmCapabilityChange()
        #expect(model.pendingCapabilityReview == nil)
        #expect(model.state.snapshot == promoted)

        await model.requestCapabilityChange(.voice, to: .learning)
        #expect(model.pendingCapabilityReview == nil)
        #expect(model.state.snapshot == demoted)
    }

    @Test func privacySummarySeparatesChosenStateFromOperationalAvailability() {
        let capability = CapabilityOverview(id: .voice, chosenState: .trusted, availability: .unavailable, decidedAtMS: 1)
        #expect(capability.chosenState == .trusted)
        #expect(capability.availability == .unavailable)
        #expect(YouPrivacyCopy.readableData == "Career profile and capability choices")
        #expect(YouPrivacyCopy.encryptedLocation == "Encrypted on this device")
        #expect(YouPermissionGuidance.microphone(.notDetermined).requestsPermission == false)
    }

    @Test func diagnosticsAreAllowlistedContentFreeAndDeterministic() {
        let facts = YouOperationalFacts(store: .degraded, recovery: .ready, microphone: .denied, gateway: .unavailable, appProtection: .enabled)
        let rows = YouDiagnostics.rows(for: facts)

        #expect(rows.map(\.id) == [.localStore, .recovery, .microphone, .voiceGateway, .appProtection])
        #expect(rows.map(\.value) == ["Degraded", "Ready", "Not allowed", "Unavailable", "Enabled"])
        #expect(rows.allSatisfy { !$0.value.contains("/") && !$0.value.contains("http") })
    }
}

private func profile(name: String) -> ProfileRecord { .init(id: "11111111-1111-4111-8111-111111111111", displayName: name, headline: "", biography: "", updatedAtMS: 1) }
private func snapshot(profile: ProfileRecord?, capabilities: [CapabilityOverview] = []) -> YouSnapshot { .init(profile: profile, capabilities: capabilities, diagnostics: .unknown) }
