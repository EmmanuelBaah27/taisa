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
    private(set) var showsCareerWork = false
    private(set) var navigationDirection: NavigationDirection = .forward
    private(set) var conversationRoute: ConversationRoute?
    private(set) var conversationReturnGeneration = 0
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
    var primaryPageBottomReservation: CGFloat {
        selection == .conversations ? 0 : TaisaControlMetric.primaryNavigationReservedHeight
    }

    func select(_ destination: PrimaryDestination) {
        if destination == .careerWork {
            showCareerWork()
            return
        }
        let destinations = PrimaryDestination.allCases
        let currentIndex = destinations.firstIndex(of: selection) ?? 0
        let nextIndex = destinations.firstIndex(of: destination) ?? currentIndex
        navigationDirection = nextIndex >= currentIndex ? .forward : .backward
        selection = destination
        showsCareerWork = false
    }

    func showCareerWork() {
        select(.home)
        showsCareerWork = true
    }

    func selectAdjacent(offset: Int) {
        let destinations = PrimaryDestination.allCases
        guard let currentIndex = destinations.firstIndex(of: selection) else { return }
        let nextIndex = min(max(currentIndex + offset, destinations.startIndex), destinations.index(before: destinations.endIndex))
        select(destinations[nextIndex])
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
        conversationReturnGeneration += 1
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
    @State var model: PrimaryAppShellModel
    @State private var swipeStartSelection: PrimaryDestination?
    let homeModel: HomeModel
    var careerWorkModel: CareerWorkModel = CareerWorkModel(client: .init(loadOverview: { .init(active: [], paused: [], completed: [], archived: []) }))
    let conversationsModel: ConversationsModel
    let conversationFactory: ConversationRuntimeFactory?
    var youModel: YouModel? = nil
    var openRecovery: () -> Void = {}
    var openPersonalQA: (() -> Void)?
    var openInsights: () -> Void = {}

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationStack {
                TabView(selection: Binding(
                    get: { model.selection },
                    set: { destination in model.select(destination) }
                )) {
                    ForEach(PrimaryDestination.allCases, id: \.self) { destination in
                        destinationView(destination)
                            .tag(destination)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .simultaneousGesture(primaryPageCompletionGesture)
                .safeAreaPadding(.bottom, model.primaryPageBottomReservation)
            }

            if model.showsConversationDock {
                PageEdgeFade(.navigation)
                    .frame(maxWidth: .infinity)
                    .frame(height: 104)
                    .ignoresSafeArea(edges: [.horizontal, .bottom])
                    .allowsHitTesting(false)

                VStack(spacing: TaisaSpacing.compact.rawValue) {
                    ConversationEntryDock(
                        onVoice: { model.presentNewConversation(.voice) },
                        onKeyboard: { model.presentNewConversation(.text) }
                    )
                    .zIndex(1)
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
                .padding(.top, TaisaSpacing.section.rawValue)
                .padding(.bottom, TaisaSpacing.compact.rawValue)
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

    /// Lets the native pager own the interactive motion, then only completes a
    /// clearly horizontal page gesture when nested scroll content consumed it.
    private var primaryPageCompletionGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { _ in
                if swipeStartSelection == nil { swipeStartSelection = model.selection }
            }
            .onEnded { value in
                let startSelection = swipeStartSelection
                swipeStartSelection = nil
                guard let startSelection,
                      model.selection == startSelection,
                      abs(value.translation.width) > abs(value.translation.height),
                      abs(value.translation.width) >= 60
                else { return }
                model.selectAdjacent(offset: value.translation.width < 0 ? 1 : -1)
            }
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
    private func destinationView(_ destination: PrimaryDestination) -> some View {
        switch destination {
        case .home:
            if model.showsCareerWork {
                CareerWorkView(model: careerWorkModel, openRecovery: openRecovery)
            } else {
                HomeView(
                    model: homeModel,
                    send: openHomeIntent,
                    openRecovery: openRecovery,
                    openPersonalQA: openPersonalQA,
                    openInsights: openInsights,
                    ownsNavigation: false,
                    showsRecentConversations: false
                )
            }
        case .careerWork:
            CareerWorkView(model: careerWorkModel, openRecovery: openRecovery)
        case .conversations:
            ConversationsView(
                model: conversationsModel,
                resetID: model.conversationReturnGeneration,
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
            model.showCareerWork()
            Task { await careerWorkModel.select(.goal(id: id)) }
        case let .action(id):
            model.showCareerWork()
            Task { await careerWorkModel.select(.action(id: id)) }
        case let .milestone(goalID):
            model.showCareerWork()
            Task { await careerWorkModel.select(.goal(id: goalID)) }
        }
    }
}
