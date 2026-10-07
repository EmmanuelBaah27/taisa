import SwiftUI

struct AppRootView: View {
    @State var runtime: AppRuntime
    @State private var showsPersonalQA = false
    @State private var showsInsights = false

    var body: some View {
        Group {
            switch runtime.state {
            case .startup:
                ProgressView("Opening Taisa…")
            case .ready:
                if let model = runtime.homeModel {
                    HomeView(
                        model: model,
                        openRecovery: runtime.requireRecovery,
                        openPersonalQA: personalQAAction,
                        openInsights: { showsInsights = true }
                    )
                }
            case .recoveryRequired:
                NavigationStack {
                    RecoveryView()
                        .accessibilityIdentifier("home.recovery")
                }
            }
        }
        .task { await runtime.start() }
#if TAISA_PERSONAL
        .sheet(isPresented: $showsPersonalQA) {
            NavigationStack { PersonalDeviceQAView() }
        }
#endif
        .sheet(isPresented: $showsInsights) {
            if let model = runtime.insightsModel {
                NavigationStack { InsightsView(model: model) }
            }
        }
    }

    private var personalQAAction: (() -> Void)? {
#if TAISA_PERSONAL
        guard ProcessInfo.processInfo.arguments.contains(PersonalDeviceQA.launchArgument) else { return nil }
        return { showsPersonalQA = true }
#else
        return nil
#endif
    }
}
