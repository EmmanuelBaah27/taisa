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
    private(set) var selection: PrimaryDestination
    private(set) var workDestination: WorkDestination?
    private(set) var selectedTaskID: String?
    private(set) var conversationRoute: ConversationRoute?
    private(set) var conversationReturnGeneration = 0
    @ObservationIgnored private var pendingEntryIntent: ConversationEntryIntent?
    @ObservationIgnored private let makeConversationID: () -> String

    init(
        selection: PrimaryDestination = .home,
        makeConversationID: @escaping () -> String = { UUID().uuidString }
    ) {
        self.selection = selection
        selectedTaskID = nil
        self.makeConversationID = makeConversationID
    }

    var showsConversationDock: Bool { conversationRoute == nil }

    func select(_ destination: PrimaryDestination) {
        selection = destination
        workDestination = nil
    }

    func showWork(_ destination: WorkDestination) {
        selection = .home
        workDestination = destination
    }

    func dismissWork() { workDestination = nil }

    func presentTask(id: String) {
        selectedTaskID = id
    }

    func dismissTask() {
        selectedTaskID = nil
    }

    func selectAdjacent(offset: Int) {
        let destinations = PrimaryDestination.allCases
        guard let currentIndex = destinations.firstIndex(of: selection) else { return }
        let nextIndex = min(
            max(currentIndex + offset, destinations.startIndex),
            destinations.index(before: destinations.endIndex)
        )
        select(destinations[nextIndex])
    }

    func presentNewConversation(_ intent: ConversationEntryIntent) {
        guard conversationRoute == nil else { return }
        conversationRoute = ConversationRoute(
            id: makeConversationID(),
            localTitle: "New chat"
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
            .navigationDestination(item: Binding(
                get: { model.workDestination },
                set: { if $0 == nil { model.dismissWork() } }
            )) { destination in
                workDestinationView(destination)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.showsConversationDock {
                TaisaBottomChrome {
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
        .sheet(isPresented: taskDetailPresented, onDismiss: refreshHomeAfterTaskDetail) {
            if let actionID = model.selectedTaskID {
                TaisaExpandableSheet {
                    TaskDetailSheetContent(
                        model: careerWorkModel,
                        actionID: actionID,
                        openRecovery: openRecovery,
                        open: openTaskDetailRoute,
                        taskChanged: { Task { await homeModel.load() } },
                        dismiss: { model.dismissTask() }
                    )
                }
            }
        }
    }

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

    private var taskDetailPresented: Binding<Bool> {
        Binding(
            get: { model.selectedTaskID != nil },
            set: { if !$0 { model.dismissTask() } }
        )
    }

    private func refreshHomeAfterTaskDetail() {
        careerWorkModel.returnToOverview()
        Task { await homeModel.load() }
    }

    private func openTaskDetailRoute(_ route: CareerWorkRoute) {
        switch route {
        case let .action(id):
            model.presentTask(id: id)
        case .goal, .evidence:
            model.dismissTask()
            model.showWork(.goals(route: route))
        case .overview:
            model.dismissTask()
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
            HomeView(
                model: homeModel,
                send: openHomeIntent,
                openRecovery: openRecovery,
                openPersonalQA: openPersonalQA,
                openInsights: openInsights,
                ownsNavigation: false,
                showsRecentConversations: false
            )
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
                ContentUnavailableView {
                    VStack {
                        CentralIcon(.peopleCircle).frame(width: 32, height: 32)
                        TaisaText(role: .heading, content: "You is unavailable")
                    }
                } description: {
                    TaisaText(role: .body, color: .mutedForeground, content: "Your local profile could not be opened.")
                }
                    .navigationTitle("You")
                    .accessibilityIdentifier("you.unavailable")
            }
        }
    }

    @ViewBuilder
    private func workDestinationView(_ destination: WorkDestination) -> some View {
        switch destination {
        case let .tasks(route):
            TasksView(model: careerWorkModel, initialRoute: route, openRecovery: openRecovery)
        case let .goals(route):
            GoalsView(model: careerWorkModel, initialRoute: route, openRecovery: openRecovery)
        }
    }

    private func openHomeIntent(_ intent: HomeIntent) {
        switch intent {
        case let .conversation(id): model.openConversation(id: id, title: "Conversation")
        case let .goal(id):
            model.showWork(.goals(route: .goal(id: id)))
        case let .action(id): model.presentTask(id: id)
        case let .milestone(goalID):
            model.showWork(.goals(route: .goal(id: goalID)))
        case .actions:
            model.showWork(.tasks(route: nil))
        case .goals:
            model.showWork(.goals(route: nil))
        }
    }
}
