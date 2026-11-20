import SwiftUI
import TaisaStorage
import TaisaYou

struct YouScenarioView: View {
    @State private var model: YouModel
    @State private var showsRecovery = false

    init(mode: YouScenarioMode) {
        let client: YouClient
        switch mode {
        case .recoveryRequired:
            client = .init(load: { throw StorageError.authenticationFailed })
        case .failure:
            client = .init(load: { throw YouContractError.persistenceFailed })
        case .content, .permissionDenied, .gatewayUnavailable:
            let store = YouPreviewProfileStore(snapshot: Self.snapshot(mode: mode))
            client = .init(load: { await store.load() }, saveProfile: { try await store.save($0) })
        }
        _model = State(initialValue: YouModel(client: client))
    }

    var body: some View {
        YouView(model: model, openRecovery: { showsRecovery = true })
        .sheet(isPresented: $showsRecovery) {
            NavigationStack {
                ContentUnavailableView("Backup and recovery", systemImage: "lock.shield", description: Text("This preview route composes the existing secure recovery flow."))
                    .toolbar { Button("Close") { showsRecovery = false } }
            }
        }
        .frame(minHeight: 700)
    }

    nonisolated private static func snapshot(mode: YouScenarioMode) -> YouSnapshot {
        let permission: YouPermissionStatus = mode == .permissionDenied ? .denied : .granted
        let gateway: YouHealth = mode == .gatewayUnavailable ? .unavailable : .healthy
        return .init(
            profile: .init(
                id: "10000000-0000-4000-8000-000000000049",
                displayName: "Baah",
                biography: "Product designer at Oyster",
                updatedAtMS: 1
            ),
            diagnostics: .init(store: .healthy, recovery: .ready, microphone: permission, gateway: gateway, appProtection: .enabled)
        )
    }
}

private actor YouPreviewProfileStore {
    private var snapshot: YouSnapshot
    init(snapshot: YouSnapshot) { self.snapshot = snapshot }
    func load() -> YouSnapshot { snapshot }
    func save(_ draft: ProfileDraft) throws -> YouSnapshot {
        guard ProfileInputValidator.validate(
            displayName: draft.displayName,
            biography: draft.biography
        ).isValid else { throw YouContractError.invalidProfile }
        snapshot = .init(profile: .init(
            id: snapshot.profile?.id ?? "10000000-0000-4000-8000-000000000049",
            displayName: draft.displayName,
            biography: draft.biography, updatedAtMS: 1), diagnostics: snapshot.diagnostics)
        return snapshot
    }
}
