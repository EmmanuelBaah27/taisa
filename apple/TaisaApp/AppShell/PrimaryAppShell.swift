import Observation
import SwiftUI
import TaisaDesignSystem
import TaisaCareerWork
import TaisaHome
import TaisaConversations
import TaisaStorage
import TaisaYou

@MainActor
@Observable
final class PrimaryAppShellModel {
    enum NavigationDirection: Sendable, Equatable { case forward, backward }

    private(set) var selection: PrimaryDestination
    private(set) var navigationDirection: NavigationDirection = .forward
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
        let destinations = PrimaryDestination.allCases
        let currentIndex = destinations.firstIndex(of: selection) ?? 0
        let nextIndex = destinations.firstIndex(of: destination) ?? currentIndex
        navigationDirection = nextIndex >= currentIndex ? .forward : .backward
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

    func dismissConversationAndRefresh(_ refresh: @MainActor () async -> Void) async {
        dismissConversation()
        await refresh()
    }

    func openConversation(id: String, title: String) {
        guard conversationRoute == nil else { return }
        conversationRoute = ConversationRoute(id: id, localTitle: title)
        pendingEntryIntent = nil
    }
}

struct PrimaryAppShell: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var model: PrimaryAppShellModel
    let homeModel: HomeModel
    var careerWorkModel: CareerWorkModel = CareerWorkModel(client: .init(loadOverview: { .init(active: [], paused: [], completed: [], archived: []) }))
    let conversationsModel: ConversationsModel
    let conversationFactory: ConversationRuntimeFactory?
    var youModel: YouModel? = nil
    var openRecovery: () -> Void = {}
    var openPersonalQA: (() -> Void)?
    var openInsights: () -> Void = {}

    var body: some View {
        NavigationStack {
            ZStack {
                destination
                    .id(model.selection)
                    .transition(destinationTransition)
            }
            .animation(reduceMotion ? nil : .smooth, value: model.selection)
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
                        items: PrimaryDestination.allCases.map { ($0, $0.title, $0.icon) },
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
            ConversationHostView(
                route: route,
                entryIntent: model.consumeEntryIntent(),
                factory: conversationFactory,
                dismiss: dismissConversationAndRefresh
            )
        }
    }

    private var destinationTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        return .opacity
    }

    @MainActor
    private func dismissConversationAndRefresh() {
        Task {
            await model.dismissConversationAndRefresh {
                await conversationsModel.load()
            }
        }
    }

    @ViewBuilder
    private var destination: some View {
        switch model.selection {
        case .home:
            HomeView(
                model: homeModel,
                send: openHomeIntent,
                openRecovery: openRecovery,
                openPersonalQA: openPersonalQA,
                openInsights: openInsights,
                ownsNavigation: false,
                showsRecentConversations: false
            )
        case .careerWork:
            CareerWorkView(model: careerWorkModel, openRecovery: openRecovery)
        case .conversations:
            ConversationsView(
                model: conversationsModel,
                resume: { model.openConversation(id: $0.conversationID, title: "Draft") },
                open: { model.openConversation(id: $0.id, title: $0.title) },
                openRecovery: openRecovery
            )
        case .you:
            if let youModel {
                YouView(model: youModel, openRecovery: openRecovery)
            } else {
                ContentUnavailableView("You is unavailable", systemImage: "person.crop.circle.badge.exclamationmark", description: Text("Your local profile could not be opened."))
                    .navigationTitle("You")
                    .accessibilityIdentifier("you.unavailable")
            }
        }
    }

    private func openHomeIntent(_ intent: HomeIntent) {
        switch intent {
        case let .conversation(id): model.openConversation(id: id, title: "Conversation")
        case let .goal(id):
            model.select(.careerWork)
            Task { await careerWorkModel.select(.goal(id: id)) }
        case let .action(id):
            model.select(.careerWork)
            Task { await careerWorkModel.select(.action(id: id)) }
        case let .milestone(goalID):
            model.select(.careerWork)
            Task { await careerWorkModel.select(.goal(id: goalID)) }
        }
    }
}
