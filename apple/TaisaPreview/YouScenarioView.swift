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
            client = .init(load: { Self.snapshot(mode: mode) })
        }
        _model = State(initialValue: YouModel(client: client))
    }

    var body: some View {
        NavigationStack {
            YouView(model: model, openRecovery: { showsRecovery = true })
        }
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
                headline: "Product builder",
                biography: "Building a private, local-first working companion.",
                updatedAtMS: 1
            ),
            capabilities: [
                .init(id: .voice, chosenState: .trial, availability: gateway == .healthy && permission == .granted ? .available : .unavailable, decidedAtMS: 1),
                .init(id: .seniorSelf, chosenState: .ready, availability: gateway == .healthy ? .available : .unavailable, decidedAtMS: 1),
                .init(id: .insights, chosenState: .trusted, availability: .available, decidedAtMS: 1),
            ],
            diagnostics: .init(store: .healthy, recovery: .ready, microphone: permission, gateway: gateway, appProtection: .enabled)
        )
    }
}
