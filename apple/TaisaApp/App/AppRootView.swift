import SwiftUI

struct AppRootView: View {
    @State var runtime: AppRuntime
    @State private var showsPersonalQA = false

    var body: some View {
        Group {
            switch runtime.state {
            case .startup:
                ProgressView("Opening Taisa…")
            case .ready:
                if let model = runtime.homeModel, let conversationsModel = runtime.conversationsModel {
                    PrimaryAppShell(
                        model: runtime.primaryShellModel,
                        homeModel: model,
                        conversationsModel: conversationsModel,
                        conversationFactory: runtime.conversationFactory,
                        openRecovery: runtime.requireRecovery,
                        openPersonalQA: personalQAAction
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
