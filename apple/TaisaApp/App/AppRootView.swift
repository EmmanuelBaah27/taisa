import Observation
import SwiftUI

@MainActor
@Observable
final class AppRootPresentationModel {
    private(set) var showsUserRecovery = false

    func openUserRecovery() { showsUserRecovery = true }
    func closeUserRecovery() { showsUserRecovery = false }
}

struct AppRootView: View {
    @State var runtime: AppRuntime
    @State private var presentation = AppRootPresentationModel()
    @State private var showsPersonalQA = false
    @State private var showsInsights = false
    @State private var startsProductVoiceAfterQA = false
    @State private var showsRuntimeRecovery = true

    var body: some View {
        Group {
            if showsConversationOverflowQA {
                ConversationView(model: .overflowQAPreview())
            } else {
                switch runtime.state {
                case .startup:
                    ProgressView("Opening Taisa…")
                case .ready:
                    if let model = runtime.homeModel, let careerWorkModel = runtime.careerWorkModel, let conversationsModel = runtime.conversationsModel {
                        PrimaryAppShell(
                            model: runtime.primaryShellModel,
                            homeModel: model,
                            careerWorkModel: careerWorkModel,
                            conversationsModel: conversationsModel,
                            conversationFactory: runtime.conversationFactory,
                            youModel: runtime.youModel,
                            openRecovery: presentation.openUserRecovery,
                            openPersonalQA: personalQAAction,
                            openInsights: { showsInsights = true }
                        )
                    }
                case .recoveryRequired:
                    if showsRuntimeRecovery { runtimeRecovery }
                    else { recoveryUnavailable }
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
                }, restoreSucceeded: { await runtime.reloadAfterRestore() == .ready })
            }
        }
#endif
        .sheet(isPresented: $showsInsights) {
            if let model = runtime.insightsModel {
                NavigationStack { InsightsView(model: model) }
            }
        }
        .sheet(isPresented: Binding(
            get: { presentation.showsUserRecovery },
            set: { if !$0 { presentation.closeUserRecovery() } }
        )) {
            NavigationStack {
                RecoveryView(
                    dismissRuntimeRecovery: presentation.closeUserRecovery,
                    restoreSucceeded: {
                        let state = await runtime.reloadAfterRestore()
                        if state == .ready { presentation.closeUserRecovery() }
                        return state == .ready
                    }
                )
            }
        }
    }

    private var runtimeRecovery: some View {
        NavigationStack {
            RecoveryView(
                retryRuntime: { Task { await runtime.retryRecovery() } },
                dismissRuntimeRecovery: { showsRuntimeRecovery = false },
                restoreSucceeded: { await runtime.reloadAfterRestore() == .ready }
            )
            .accessibilityIdentifier("home.recovery")
        }
    }

    private var recoveryUnavailable: some View {
        ContentUnavailableView {
            Label("Secure data unavailable", systemImage: "lock.trianglebadge.exclamationmark")
        } description: {
            Text("Taisa could not open the encrypted data on this device. Your data has not been replaced.")
        } actions: {
            Button("Try Again") {
                Task {
                    let state = await runtime.retryRecovery()
                    if state == .recoveryRequired { showsRuntimeRecovery = false }
                }
            }
            Button("Open backup and recovery") { showsRuntimeRecovery = true }
        }
        .accessibilityIdentifier("recovery.unavailable")
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
        if ProcessInfo.processInfo.arguments.contains("--taisa-seed-finalized-voice-draft") {
            guard runtime.state == .ready, let factory = runtime.conversationFactory else {
                print("TAISA_CONVERSATION_SEED_PROBE result=factory-unavailable")
                return
            }
            do {
                _ = try await factory.seedFinalizedVoiceDraftProbe()
                print("TAISA_CONVERSATION_SEED_PROBE result=seeded")
            } catch {
                print("TAISA_CONVERSATION_SEED_PROBE result=failed type=\(String(reflecting: type(of: error)))")
            }
        }
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
