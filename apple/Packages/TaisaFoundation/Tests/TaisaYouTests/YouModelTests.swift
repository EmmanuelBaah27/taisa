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
}

private func profile(name: String) -> ProfileRecord { .init(id: "11111111-1111-4111-8111-111111111111", displayName: name, headline: "", biography: "", updatedAtMS: 1) }
private func snapshot(profile: ProfileRecord?) -> YouSnapshot { .init(profile: profile, capabilities: [], diagnostics: .unknown) }
