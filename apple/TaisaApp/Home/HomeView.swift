import SwiftUI
import TaisaHome
import TaisaStorage

struct HomeView: View {
    @State private var model: HomeModel
    var send: (HomeIntent) -> Void = { _ in }
    var openRecovery: () -> Void = {}

    init(
        model: HomeModel,
        send: @escaping (HomeIntent) -> Void = { _ in },
        openRecovery: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: model)
        self.send = send
        self.openRecovery = openRecovery
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Home")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.load() } }
                    }
                }
        }
        .accessibilityIdentifier("home.root")
        .task { if model.state == .idle { await model.load() } }
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
                Section("Recent conversations") {
                    ForEach(snapshot.conversations, id: \.id) { ConversationRow(conversation: $0, send: send) }
                }
                .accessibilityIdentifier("home.conversations")
                Section("Active goals") {
                    ForEach(snapshot.goals, id: \.id) { GoalRow(goal: $0, send: send) }
                }
                .accessibilityIdentifier("home.goals")
                Section("Open actions") {
                    ForEach(snapshot.actions, id: \.id) { ActionRow(action: $0, send: send) }
                }
                .accessibilityIdentifier("home.actions")
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
