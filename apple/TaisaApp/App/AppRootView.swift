import SwiftUI

struct AppRootView: View {
    @State var runtime: AppRuntime

    var body: some View {
        Group {
            switch runtime.state {
            case .startup:
                ProgressView("Opening Taisa…")
            case .ready:
                if let model = runtime.homeModel {
                    HomeView(model: model, openRecovery: runtime.requireRecovery)
                }
            case .recoveryRequired:
                NavigationStack {
                    RecoveryView()
                        .accessibilityIdentifier("home.recovery")
                }
            }
        }
        .task { await runtime.start() }
    }
}
