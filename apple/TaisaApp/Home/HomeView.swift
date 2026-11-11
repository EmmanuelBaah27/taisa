import SwiftUI
import TaisaDesignSystem
import TaisaHome
import TaisaStorage

struct HomeView: View {
    @State private var model: HomeModel
    @State private var activeSheet: ThisWeekSheet?
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
        showsRecentConversations: Bool = true
    ) {
        _model = State(initialValue: model)
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
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case let .priorWeekReview(unresolvedCount):
                PriorWeekReviewSheet(unresolvedCount: unresolvedCount)
            }
        }
    }

    private var homeContent: some View {
        content
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    TaisaToolbarAction(label: "Refresh", icon: .refresh) { Task { await model.load() } }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    TaisaToolbarAction(label: "Backup and recovery", icon: .recovery, action: openRecovery)
                        .accessibilityIdentifier("foundation.recovery.action")
                }
                if let openPersonalQA {
                    ToolbarItem(placement: .topBarTrailing) {
                        TaisaToolbarAction(label: "Personal device QA", icon: .testflight, action: openPersonalQA)
                            .accessibilityIdentifier("foundation.personal-qa.action")
                    }
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("Loading Home…")
        case .empty:
            List {
                ThisWeekSection(items: [], send: send)
                HomeActionsPreviewSection(prompts: [], send: send)
                HomeGoalsSummarySection(goals: [], send: send)
            }
            .accessibilityIdentifier("home.empty")
        case let .content(snapshot, isRefreshing, issue):
            List {
                if let issue { issueRow(issue) }
                ThisWeekSection(
                    items: snapshot.thisWeek,
                    send: send
                )
                HomeActionsPreviewSection(prompts: snapshot.actionPrompts, send: send)
                HomeGoalsSummarySection(goals: snapshot.goals, send: send)
                if let leadInsight = snapshot.leadInsight {
                    LeadInsightSection(insight: leadInsight, openInsights: openInsights)
                }
                if snapshot.leadInsight == nil && snapshot.hasConfirmedInsightHistory {
                    TaisaButton(role: .secondary, label: "View insights", icon: .insights) { openInsights() }
                        .accessibilityIdentifier("home.insights.link")
                }
                if snapshot.unresolvedPriorWeekCount > 0 {
                    HomeReviewSection(unresolvedCount: snapshot.unresolvedPriorWeekCount) {
                        activeSheet = .priorWeekReview(unresolvedCount: $0)
                    }
                }
                if showsRecentConversations && !snapshot.conversations.isEmpty {
                    Section("Recent conversations") {
                        ForEach(snapshot.conversations, id: \.id) { ConversationRow(conversation: $0, send: send) }
                    }
                    .accessibilityIdentifier("home.conversations")
                }
                if isRefreshing { ProgressView().frame(maxWidth: .infinity) }
            }
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

    private func issueRow(_ issue: HomeIssue) -> some View {
        Button {
            if issue == .recoveryRequired { openRecovery() }
            else { Task { await model.load() } }
        } label: {
            TaisaRow(
                title: issue == .recoveryRequired ? "Open recovery" : "Try refresh again",
                icon: .warning,
                emphasis: .attention
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(issue == .recoveryRequired ? "home.recovery" : "home.retry")
    }
}
