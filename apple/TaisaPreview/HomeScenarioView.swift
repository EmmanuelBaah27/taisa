import SwiftUI
import TaisaHome
import TaisaStorage

struct HomeScenarioView: View {
    let mode: HomeScenarioMode
    @State private var model: HomeModel
    @State private var insightsModel: InsightsModel
    @State private var showsInsights = false

    init(mode: HomeScenarioMode) {
        self.mode = mode
        let taskStore = PreviewTaskStore(snapshot: mode == .empty ? .previewEmpty : .previewCombined)
        let state: HomeState
        switch mode {
        case .loading:
            state = .loading
        case .empty:
            state = .empty
        case .content, .taskComposer:
            state = .content(.previewContent, isRefreshing: false, issue: nil)
        case .combined, .insights:
            state = .content(.previewCombined, isRefreshing: false, issue: nil)
        case .refreshing:
            state = .content(.previewContent, isRefreshing: true, issue: nil)
        case .failure:
            state = .failure(.storageUnavailable)
        case .recovery:
            state = .failure(.recoveryRequired)
        }
        _model = State(initialValue: HomeModel(client: HomeClient(
            load: { await taskStore.load() },
            create: { try await taskStore.create(title: $0, dueDay: $1) }
        ), initialState: state))
        _insightsModel = State(initialValue: InsightsModel(client: InsightsClient(
            load: { .previewContent },
            detail: { insight in
                InsightDetailSnapshot(
                    insight: insight,
                    sources: [
                        InsightSourceRecord(
                            id: "60000000-0000-0000-0000-000000000001",
                            insightID: insight.id,
                            sourceType: "conversation",
                            sourceID: "10000000-0000-0000-0000-000000000001",
                            excerpt: "Morning planning felt clear and decisive.",
                            createdAtMS: 1_800_000_000_000
                        )
                    ],
                    revisions: [
                        InsightRevisionRecord(
                            id: "70000000-0000-0000-0000-000000000001",
                            insightID: insight.id,
                            proposedBody: insight.body,
                            status: .accepted,
                            sourceType: "conversation",
                            sourceID: "10000000-0000-0000-0000-000000000001",
                            createdAtMS: 1_800_000_000_000,
                            resolvedAtMS: 1_800_000_000_000
                        )
                    ]
                )
            }
        )))
    }

    var body: some View {
        Group {
            if mode == .insights {
                NavigationStack { InsightsView(model: insightsModel) }
            } else {
                HomeView(
                    model: model,
                    openInsights: { showsInsights = true },
                    ownsNavigation: false,
                    initiallyShowsTaskComposer: mode == .taskComposer
                )
                .sheet(isPresented: $showsInsights) {
                    NavigationStack { InsightsView(model: insightsModel) }
                }
            }
        }
        .frame(minHeight: 700)
    }
}

private actor PreviewTaskStore {
    private let snapshot: HomeSnapshot
    private var createdActions: [ActionRecord] = []

    init(snapshot: HomeSnapshot) {
        self.snapshot = snapshot
    }

    func load() -> HomeSnapshot {
        HomeSnapshot(
            conversations: snapshot.conversations,
            goals: snapshot.goals,
            milestones: snapshot.milestones,
            actions: createdActions + snapshot.actions,
            actionPrompts: snapshot.actionPrompts,
            thisWeek: snapshot.thisWeek,
            unresolvedPriorWeekCount: snapshot.unresolvedPriorWeekCount,
            overdueActions: snapshot.overdueActions,
            recentlyReopenedActions: snapshot.recentlyReopenedActions,
            actionReviewFacts: snapshot.actionReviewFacts,
            leadInsight: snapshot.leadInsight,
            hasConfirmedInsightHistory: snapshot.hasConfirmedInsightHistory
        )
    }

    func create(title: String, dueDay: ActionDueDay?) throws -> ActionRecord {
        let action = ActionRecord(
            id: UUID().uuidString,
            goalID: nil,
            title: title,
            detail: "",
            status: ActionStatus.active.rawValue,
            dueAtMS: nil,
            createdAtMS: 1_800_000_000_000,
            updatedAtMS: 1_800_000_000_000,
            dueDay: dueDay
        )
        createdActions.insert(action, at: 0)
        return action
    }
}
