import Observation
import SwiftUI
import TaisaDesignSystem
import TaisaHome

@MainActor
@Observable
final class PrimaryAppShellModel {
    private(set) var selection: PrimaryDestination
    private(set) var conversationRoute: ConversationRoute?
    @ObservationIgnored private var pendingEntryIntent: ConversationEntryIntent?
    @ObservationIgnored private let makeConversationID: () -> String

    init(
        selection: PrimaryDestination = .home,
        makeConversationID: @escaping () -> String = { UUID().uuidString }
    ) {
        self.selection = selection
        self.makeConversationID = makeConversationID
    }

    var showsConversationDock: Bool { conversationRoute == nil }

    func select(_ destination: PrimaryDestination) {
        selection = destination
    }

    func presentNewConversation(_ intent: ConversationEntryIntent) {
        guard conversationRoute == nil else { return }
        conversationRoute = ConversationRoute(
            id: makeConversationID(),
            localTitle: "New conversation"
        )
        pendingEntryIntent = intent
    }

    func consumeEntryIntent() -> ConversationEntryIntent? {
        defer { pendingEntryIntent = nil }
        return pendingEntryIntent
    }

    func dismissConversation() {
        pendingEntryIntent = nil
        conversationRoute = nil
    }
}

struct PrimaryAppShell: View {
    @State var model: PrimaryAppShellModel
    let homeModel: HomeModel
    var openRecovery: () -> Void = {}
    var openPersonalQA: (() -> Void)?

    var body: some View {
        NavigationStack {
            destination
        }
        .safeAreaInset(edge: .bottom, spacing: TaisaSpacing.compact.rawValue) {
            if model.showsConversationDock {
                VStack(spacing: TaisaSpacing.compact.rawValue) {
                    ConversationEntryDock(
                        onVoice: { model.presentNewConversation(.voice) },
                        onKeyboard: { model.presentNewConversation(.text) }
                    )
                    .accessibilityIdentifier("app-shell.conversation-dock")

                    PrimaryNavigation(
                        items: PrimaryDestination.allCases.map { ($0, $0.title, $0.systemImage) },
                        selection: Binding(
                            get: { model.selection },
                            set: { model.select($0) }
                        )
                    )
                    .accessibilityIdentifier("app-shell.primary-navigation")
                }
                .padding(.horizontal, TaisaSpacing.standard.rawValue)
            }
        }
        .fullScreenCover(item: Binding(
            get: { model.conversationRoute },
            set: { if $0 == nil { model.dismissConversation() } }
        )) { route in
            ConversationRoutePlaceholder(
                route: route,
                entryIntent: model.consumeEntryIntent(),
                dismiss: model.dismissConversation
            )
        }
    }

    @ViewBuilder
    private var destination: some View {
        switch model.selection {
        case .home:
            HomeView(
                model: homeModel,
                openRecovery: openRecovery,
                openPersonalQA: openPersonalQA,
                ownsNavigation: false,
                showsRecentConversations: false
            )
        case .conversations:
            ContentUnavailableView(
                "No conversations yet",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Completed conversations and saved drafts will appear here.")
            )
            .navigationTitle("Conversations")
            .accessibilityIdentifier("conversations.root")
        case .you:
            ContentUnavailableView(
                "You",
                systemImage: "person",
                description: Text("Your settings and preferences will appear here.")
            )
            .navigationTitle("You")
            .accessibilityIdentifier("you.root")
        }
    }
}

private struct ConversationRoutePlaceholder: View {
    let route: ConversationRoute
    let entryIntent: ConversationEntryIntent?
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                route.localTitle,
                systemImage: entryIntent == .voice ? "waveform" : "keyboard",
                description: Text(entryIntent == .voice ? "Preparing voice conversation…" : "Preparing text conversation…")
            )
            .navigationTitle(route.localTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: dismiss)
                }
            }
        }
        .accessibilityIdentifier("conversation.root")
    }
}
