import SwiftUI
import TaisaDesignSystem
import TaisaHome
import TaisaStorage

struct HomeView: View {
    @State private var model: HomeModel
    @State private var activeSheet: ThisWeekSheet?
    @State private var showsTaskComposer = false
    @State private var taskTitle = ""
    @State private var taskDueDate: Date?
    @State private var showsTaskAddedToast = false
    var send: (HomeIntent) -> Void = { _ in }
    var openRecovery: () -> Void = {}
    var openPersonalQA: (() -> Void)?
    var openInsights: () -> Void = {}
    private let ownsNavigation: Bool
    private let showsRecentConversations: Bool

    init(
        model: HomeModel,
        send: @escaping (HomeIntent) -> Void = { _ in },
        openRecovery: @escaping () -> Void = {},
        openPersonalQA: (() -> Void)? = nil,
        openInsights: @escaping () -> Void = {},
        ownsNavigation: Bool = true,
        showsRecentConversations: Bool = true,
        initiallyShowsTaskComposer: Bool = false
    ) {
        _model = State(initialValue: model)
        _showsTaskComposer = State(initialValue: initiallyShowsTaskComposer)
        self.send = send
        self.openRecovery = openRecovery
        self.openPersonalQA = openPersonalQA
        self.openInsights = openInsights
        self.ownsNavigation = ownsNavigation
        self.showsRecentConversations = showsRecentConversations
    }

    var body: some View {
        Group {
            if ownsNavigation { NavigationStack { homeContent } }
            else { homeContent }
        }
        .accessibilityIdentifier("home.root")
        .task { if model.state == .idle { await model.load() } }
        .fullScreenCover(isPresented: $showsTaskComposer) {
            taskComposerPresentationLayer
                .presentationBackground(.clear)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case let .priorWeekReview(unresolvedCount):
                PriorWeekReviewSheet(unresolvedCount: unresolvedCount)
            }
        }
    }

    private var homeContent: some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                TaisaDatedPageHeader(date: Date().taskHeaderLabel, title: "Up late, Beats?") { EmptyView() }
            }
            .overlay(alignment: .top) {
                if showsTaskAddedToast {
                    TaisaToast(message: "Task added", style: .light) { showsTaskAddedToast = false }
                        .padding(.top, TaisaSpacing.compact.rawValue)
                }
            }
    }

    private var taskComposerPresentationLayer: some View {
        ZStack(alignment: .bottom) {
            TaisaColor.foreground.color
                .opacity(TaisaEffect.taskComposerBackdropOpacity)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissTaskComposer() }
                .accessibilityHidden(true)

            TaskComposerView(title: $taskTitle, dueDate: $taskDueDate, submit: submitTask)
                .accessibilityIdentifier("home.tasks.composer")
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .idle, .loading:
            TaisaProgressView("Loading Home…")
        case .empty:
            ScrollView {
                HomeActionsPreviewSection(actions: [], totalCount: 0, send: send, add: { showsTaskComposer = true })
                    .padding(.horizontal, TaisaSpacing.content.rawValue)
                    .padding(.top, TaisaSpacing.section.rawValue)
            }
            .background(TaisaColor.background.color)
            .accessibilityIdentifier("home.empty")
        case let .content(snapshot, isRefreshing, issue):
            ScrollView {
                VStack(spacing: TaisaSpacing.control.rawValue) {
                if let issue { issueRow(issue) }
                HomeActionsPreviewSection(actions: snapshot.actions, totalCount: snapshot.actions.count, send: send, add: { showsTaskComposer = true })
                if isRefreshing { ProgressView().frame(maxWidth: .infinity) }
                }
                .padding(.horizontal, TaisaSpacing.content.rawValue)
                .padding(.top, TaisaSpacing.section.rawValue)
            }
            .background(TaisaColor.background.color)
            .refreshable { await model.load() }
        case let .failure(issue):
            ContentUnavailableView {
                VStack {
                    CentralIcon(.warning).frame(width: 32, height: 32)
                    TaisaText(role: .heading, content: issue == .recoveryRequired ? "Recovery required" : "Home unavailable")
                }
            } description: {
                TaisaText(role: .body, color: .mutedForeground, content: issue == .recoveryRequired ? "Open recovery to restore secure access." : "Taisa couldn’t read your Home securely.")
            } actions: {
                if issue == .recoveryRequired {
                    TaisaButton(role: .primary, label: "Open recovery", icon: .recovery) { openRecovery() }
                        .accessibilityIdentifier("home.recovery")
                } else {
                    TaisaButton(role: .primary, label: "Try again", icon: .refresh) { Task { await model.load() } }
                        .accessibilityIdentifier("home.retry")
                }
            }
            .accessibilityIdentifier(issue == .recoveryRequired ? "home.recovery" : "home.failure")
        }
    }

    private func submitTask() {
        let title = taskTitle
        let dueDay = taskDueDate.flatMap(\.actionDueDay)
        Task {
            if await model.createTask(title: title, dueDay: dueDay) {
                taskTitle = ""
                taskDueDate = nil
                showsTaskComposer = false
                showsTaskAddedToast = true
            }
        }
    }

    private func dismissTaskComposer() {
        showsTaskComposer = false
    }

    private func issueRow(_ issue: HomeIssue) -> some View {
        TaisaPressable(action: {
            if issue == .recoveryRequired { openRecovery() }
            else { Task { await model.load() } }
        }) {
            TaisaRow(
                title: issue == .recoveryRequired ? "Open recovery" : "Try refresh again",
                icon: .warning,
                emphasis: .attention
            )
        }
        .accessibilityIdentifier(issue == .recoveryRequired ? "home.recovery" : "home.retry")
    }
}

private extension Date {
    var taskHeaderLabel: String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: self)
    }

    var actionDueDay: ActionDueDay? {
        let values = Calendar.current.dateComponents([.year, .month, .day], from: self)
        guard let year = values.year, let month = values.month, let day = values.day else { return nil }
        return ActionDueDay(rawValue: String(format: "%04d-%02d-%02d", year, month, day))
    }
}
