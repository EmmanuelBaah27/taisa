import SwiftUI

struct AppRootView: View {
    @State var runtime: AppRuntime
    @State private var showsPersonalQA = false
    @State private var startsProductVoiceAfterQA = false

    var body: some View {
        Group {
            if showsConversationOverflowQA {
                ConversationView(model: .overflowQAPreview())
            } else {
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
        }
        .task { await runtime.start() }
#if TAISA_PERSONAL
        .sheet(isPresented: $showsPersonalQA, onDismiss: openPendingProductVoiceQA) {
            NavigationStack {
                PersonalDeviceQAView(openProductVoice: {
                    startsProductVoiceAfterQA = true
                    showsPersonalQA = false
                })
            }
        }
#endif
    }

    private var showsConversationOverflowQA: Bool {
#if DEBUG || TAISA_PERSONAL
        ProcessInfo.processInfo.arguments.contains("--taisa-conversation-overflow-qa")
#else
        false
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

    private func openPendingProductVoiceQA() {
        guard startsProductVoiceAfterQA else { return }
        startsProductVoiceAfterQA = false
        runtime.primaryShellModel.presentNewConversation(.voice)
    }
}
