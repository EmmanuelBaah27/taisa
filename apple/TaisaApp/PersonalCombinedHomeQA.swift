#if TAISA_PERSONAL
import Foundation
import SwiftUI
import TaisaHome
import TaisaStorage

@MainActor
enum PersonalCombinedHomeQA {
    struct Fixture {
        let home: HomeModel
        let insights: InsightsModel
    }

    static func fixture() -> Fixture {
        let store = PersonalCombinedHomeQAStore()
        let home = HomeModel(client: HomeClient(
            load: { await store.homeSnapshot() },
            complete: { try await store.complete(actionID: $0) },
            restore: { await store.restore($0) },
            place: { await store.move(actionID: $0, weekContaining: $1, plannedDay: $2) },
            move: { await store.move(actionID: $0, weekContaining: $1, plannedDay: $2) }
        ))
        let insights = InsightsModel(client: InsightsClient(
            load: { PersonalCombinedHomeQAFixtures.insights },
            detail: { PersonalCombinedHomeQAFixtures.detail(for: $0) }
        ))
        return Fixture(home: home, insights: insights)
    }
}

private actor PersonalCombinedHomeQAStore {
    private var item: WeeklyWorkItem? = PersonalCombinedHomeQAFixtures.weeklyItem

    func homeSnapshot() -> HomeSnapshot {
        HomeSnapshot(
            conversations: PersonalCombinedHomeQAFixtures.conversations,
            goals: PersonalCombinedHomeQAFixtures.goals,
            actions: PersonalCombinedHomeQAFixtures.actions,
            thisWeek: item.map { [$0] } ?? [],
            unresolvedPriorWeekCount: 2,
            leadInsight: PersonalCombinedHomeQAFixtures.currentInsight,
            hasConfirmedInsightHistory: true
        )
    }

    func complete(actionID: String) throws -> WeeklyWorkUndoToken {
        guard let current = item, current.action.id == actionID else {
            throw HomeClientError.mutationUnavailable
        }
        item = nil
        return WeeklyWorkUndoToken(action: current.action)
    }

    func restore(_ token: WeeklyWorkUndoToken) {
        guard token.action.id == PersonalCombinedHomeQAFixtures.weeklyItem.action.id else { return }
        item = PersonalCombinedHomeQAFixtures.weeklyItem
    }

    func move(actionID: String, weekContaining: Date, plannedDay: Date?) {
        guard let current = item, current.action.id == actionID else { return }
        let calendar = Calendar(identifier: .iso8601)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: weekContaining)?.start ?? weekContaining
        item = WeeklyWorkItem(
            action: current.action,
            placement: WeeklyPlacementRecord(
                id: current.placement.id,
                actionID: actionID,
                weekStartMS: PersonalCombinedHomeQAFixtures.milliseconds(weekStart),
                plannedDayMS: plannedDay.map(PersonalCombinedHomeQAFixtures.milliseconds),
                createdAtMS: current.placement.createdAtMS,
                updatedAtMS: PersonalCombinedHomeQAFixtures.nowMS
            )
        )
    }
}

private enum PersonalCombinedHomeQAFixtures {
    static let nowMS: Int64 = 1_799_884_800_000
    static let conversationID = "10000000-0000-4000-8000-000000000001"
    static let goalID = "20000000-0000-4000-8000-000000000001"
    static let actionID = "30000000-0000-4000-8000-000000000001"

    static let conversations = [ConversationRecord(
        id: conversationID, title: "QA fixture — plan the garden studio",
        createdAtMS: nowMS - 10_000, updatedAtMS: nowMS
    )]
    static let goals = [GoalRecord(
        id: goalID, title: "QA fixture — finish the studio", detail: "Isolated sample data",
        status: "active", createdAtMS: nowMS - 10_000, updatedAtMS: nowMS
    )]
    static let actions = [ActionRecord(
        id: actionID, goalID: goalID, title: "QA fixture — draft the lighting plan",
        detail: "Tap to change the planned day", status: "open", dueAtMS: nil,
        createdAtMS: nowMS - 10_000, updatedAtMS: nowMS
    )]
    static let weeklyItem = WeeklyWorkItem(
        action: actions[0],
        placement: WeeklyPlacementRecord(
            id: "40000000-0000-4000-8000-000000000001", actionID: actionID,
            weekStartMS: nowMS - 172_800_000, plannedDayMS: nowMS,
            createdAtMS: nowMS - 10_000, updatedAtMS: nowMS
        )
    )
    static let currentInsight = InsightRecord(
        id: "50000000-0000-4000-8000-000000000001",
        body: "QA fixture — focused planning works best before midday.",
        status: .confirmed, isTimeSensitive: true, homeEligibleUntilMS: 1_900_000_000_000,
        createdAtMS: nowMS - 20_000, updatedAtMS: nowMS
    )
    static let reviewInsight = InsightRecord(
        id: "50000000-0000-4000-8000-000000000002",
        body: "QA fixture — studio work may be crowding out recovery time.",
        status: .reviewNeeded, isTimeSensitive: false, homeEligibleUntilMS: nil,
        createdAtMS: nowMS - 30_000, updatedAtMS: nowMS - 10_000
    )
    static let historicalInsight = InsightRecord(
        id: "50000000-0000-4000-8000-000000000003",
        body: "QA fixture — short daily sessions kept the plan moving.",
        status: .superseded, isTimeSensitive: false, homeEligibleUntilMS: nil,
        createdAtMS: nowMS - 40_000, updatedAtMS: nowMS - 20_000
    )
    static let insights = InsightsSnapshot(
        current: [currentInsight], reviewNeeded: [reviewInsight], history: [historicalInsight]
    )

    static func detail(for insight: InsightRecord) -> InsightDetailSnapshot {
        InsightDetailSnapshot(
            insight: insight,
            sources: [InsightSourceRecord(
                id: "60000000-0000-4000-8000-000000000001", insightID: insight.id,
                sourceType: "conversation", sourceID: conversationID,
                excerpt: "QA fixture — morning planning felt clear and decisive.", createdAtMS: nowMS
            )],
            revisions: [InsightRevisionRecord(
                id: "70000000-0000-4000-8000-000000000001", insightID: insight.id,
                proposedBody: insight.body, status: .accepted, sourceType: "conversation",
                sourceID: conversationID, createdAtMS: nowMS, resolvedAtMS: nowMS
            )]
        )
    }

    static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }
}

struct PersonalCombinedHomeQAView: View {
    @State private var home: HomeModel
    @State private var insights: InsightsModel
    @State private var showsInsights = false

    init() {
        let fixture = PersonalCombinedHomeQA.fixture()
        _home = State(initialValue: fixture.home)
        _insights = State(initialValue: fixture.insights)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Isolated QA fixtures — your Personal data is not changed")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)
                .accessibilityIdentifier("personal-qa.combined-home.notice")
            HomeView(model: home, openInsights: { showsInsights = true }, ownsNavigation: false)
        }
        .navigationTitle("Home and Insights QA")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsInsights) {
            NavigationStack { InsightsView(model: insights) }
        }
        .accessibilityIdentifier("personal-qa.combined-home")
    }
}
#endif
