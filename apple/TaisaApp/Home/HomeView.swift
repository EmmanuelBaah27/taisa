import SwiftUI
import TaisaHome
import TaisaStorage

struct HomeView: View {
    @State private var model: HomeModel
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
    }

    private var homeContent: some View {
        content
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.load() } }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Backup and recovery", systemImage: "lock.shield", action: openRecovery)
                        .accessibilityIdentifier("foundation.recovery.action")
                }
                if let openPersonalQA {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Personal device QA", action: openPersonalQA)
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
            ContentUnavailableView(
                "Nothing here yet",
                systemImage: "house",
                description: Text("Your recent conversations, active goals, and open actions will appear here.")
            )
            .accessibilityIdentifier("home.empty")
        case let .content(snapshot, isRefreshing, issue):
            List {
                if let issue { issueRow(issue) }
                if let leadInsight = snapshot.leadInsight {
                    LeadInsightSection(insight: leadInsight, openInsights: openInsights)
                }
                ThisWeekSection(
                    items: snapshot.thisWeek,
                    unresolvedPriorWeekCount: snapshot.unresolvedPriorWeekCount,
                    model: model
                )
                if snapshot.leadInsight == nil && snapshot.hasConfirmedInsightHistory {
                    Button("View insights", systemImage: "lightbulb", action: openInsights)
                        .font(.subheadline)
                        .accessibilityIdentifier("home.insights.link")
                }
                if showsRecentConversations && !snapshot.conversations.isEmpty {
                    Section("Recent conversations") {
                        ForEach(snapshot.conversations, id: \.id) { ConversationRow(conversation: $0, send: send) }
                    }
                    .accessibilityIdentifier("home.conversations")
                }
                if !snapshot.goals.isEmpty {
                    Section("Active goals") {
                        ForEach(snapshot.goals, id: \.id) { GoalRow(goal: $0, send: send) }
                    }
                    .accessibilityIdentifier("home.goals")
                }
                if !snapshot.actions.isEmpty {
                    Section("Open actions") {
                        ForEach(snapshot.actions, id: \.id) { ActionRow(action: $0, send: send) }
                    }
                    .accessibilityIdentifier("home.actions")
                }
                if isRefreshing { ProgressView().frame(maxWidth: .infinity) }
            }
            .refreshable { await model.load() }
        case let .failure(issue):
            ContentUnavailableView {
                Label(issue == .recoveryRequired ? "Recovery required" : "Home unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(issue == .recoveryRequired ? "Open recovery to restore secure access." : "Taisa couldn’t read your Home securely.")
            } actions: {
                if issue == .recoveryRequired {
                    Button("Open recovery", action: openRecovery)
                        .accessibilityIdentifier("home.recovery")
                } else {
                    Button("Try again") { Task { await model.load() } }
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
            Label(issue == .recoveryRequired ? "Open recovery" : "Try refresh again", systemImage: "exclamationmark.triangle")
        }
        .foregroundStyle(.secondary)
        .accessibilityIdentifier(issue == .recoveryRequired ? "home.recovery" : "home.retry")
    }
}
