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
                        RecoveryView(retryRuntime: {
                            Task { await runtime.retryRecovery() }
                        })
                            .accessibilityIdentifier("home.recovery")
                    }
                }
            }
        }
        .task {
            await runtime.start()
            await openPreservedDraftProbeIfRequested()
        }
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

    @MainActor
    private func openPreservedDraftProbeIfRequested() async {
#if DEBUG || TAISA_PERSONAL
        if ProcessInfo.processInfo.arguments.contains("--taisa-cleanup-completed-preserved-draft") {
            guard runtime.state == .ready, let factory = runtime.conversationFactory else {
                print("TAISA_CONVERSATION_CLEANUP_PROBE result=factory-unavailable")
                return
            }
            print("TAISA_CONVERSATION_CLEANUP_PROBE \(await factory.cleanupCompletedPreservedDraftProbe())")
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--taisa-retry-latest-preserved-draft-once") {
            guard runtime.state == .ready, let factory = runtime.conversationFactory else {
                print("TAISA_CONVERSATION_RETRY_PROBE result=factory-unavailable")
                return
            }
            print("TAISA_CONVERSATION_RETRY_PROBE \(await factory.retryLatestPreservedDraftProbe())")
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--taisa-diagnose-latest-preserved-draft") {
            guard runtime.state == .ready, let factory = runtime.conversationFactory else {
                print("TAISA_CONVERSATION_DRAFT_DIAGNOSTIC result=factory-unavailable")
                return
            }
            print("TAISA_CONVERSATION_DRAFT_DIAGNOSTIC \(await factory.contentFreeLatestDraftDiagnostic())")
            return
        }
        guard ProcessInfo.processInfo.arguments.contains("--taisa-open-first-preserved-draft"),
              runtime.state == .ready,
              let conversations = runtime.conversationsModel
        else { return }
        await conversations.load()
        guard let draft = conversations.snapshot.drafts.first else {
            print("TAISA_CONVERSATION_OPEN_PROBE result=no-draft")
            return
        }
        print("TAISA_CONVERSATION_OPEN_PROBE result=opening-draft")
        runtime.primaryShellModel.openConversation(id: draft.conversationID, title: "Draft")
#endif
    }
}
