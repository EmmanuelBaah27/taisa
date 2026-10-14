import SwiftUI
import TaisaHome
import TaisaPreviewSupport
import TaisaStorage

@MainActor
enum HomeScenarios {
    static let scenarios: [PreviewScenario] = [
        scenario("home.loading", "Home loading", .adaptive, mode: .loading),
        scenario("home.empty", "Home empty", .adaptive, mode: .empty),
        scenario("home.content", "Home content", .adaptive, mode: .content),
        scenario("home.combined", "Home combined", .adaptive, mode: .combined),
        scenario("home.insights", "Home insights", .adaptive, mode: .insights),
        scenario("home.refreshing", "Home refreshing", .adaptive, mode: .refreshing),
        scenario("home.failure", "Home failure", .adaptive, mode: .failure),
        scenario("home.recovery", "Home recovery", .adaptive, mode: .recovery),
        scenario(
            "home.accessibilityText",
            "Home accessibility text",
            .phone,
            accessibility: .init(contentSize: .accessibilityExtraExtraExtraLarge),
            mode: .combined
        ),
        scenario("home.narrowIPad", "Home narrow iPad", .tablet, mode: .content),
    ]

    private static func scenario(
        _ identifier: String,
        _ title: String,
        _ family: PreviewDeviceFamily,
        accessibility: PreviewAccessibilitySettings = .default,
        mode: HomeScenarioMode
    ) -> PreviewScenario {
        PreviewScenario(
            identifier: identifier,
            title: title,
            deviceFamily: family,
            accessibility: accessibility,
            readiness: .ready
        ) {
            AnyView(HomeScenarioView(mode: mode))
        }
    }
}

enum HomeScenarioMode: Sendable, Equatable {
    case loading
    case empty
    case content
    case combined
    case insights
    case refreshing
    case failure
    case recovery
}

extension HomeSnapshot {
    static let previewEmpty = HomeSnapshot(conversations: [], goals: [], actions: [])

    static let previewContent = HomeSnapshot(
        conversations: [
            ConversationRecord(id: "10000000-0000-0000-0000-000000000001", title: "Plan the garden studio", createdAtMS: 1, updatedAtMS: 4)
        ],
        goals: [
            GoalRecord(id: "20000000-0000-0000-0000-000000000001", title: "Finish the studio", detail: "A fictional preview goal", status: "active", createdAtMS: 1, updatedAtMS: 3)
        ],
        actions: [
            ActionRecord(id: "30000000-0000-0000-0000-000000000001", goalID: nil, title: "Measure the north wall", detail: "", status: "open", dueAtMS: 1_800_000_000_000, createdAtMS: 1, updatedAtMS: 2)
        ]
    )

    static let previewCombined = HomeSnapshot(
        conversations: previewContent.conversations,
        goals: previewContent.goals,
        actions: previewContent.actions,
        thisWeek: [
            WeeklyWorkItem(
                action: ActionRecord(
                    id: "30000000-0000-0000-0000-000000000002",
                    goalID: "20000000-0000-0000-0000-000000000001",
                    title: "Draft the studio lighting plan",
                    detail: "",
                    status: "open",
                    dueAtMS: nil,
                    createdAtMS: 1,
                    updatedAtMS: 2
                ),
                placement: WeeklyPlacementRecord(
                    id: "40000000-0000-0000-0000-000000000001",
                    actionID: "30000000-0000-0000-0000-000000000002",
                    weekStartMS: 1_799_712_000_000,
                    plannedDayMS: 1_799_884_800_000,
                    createdAtMS: 1,
                    updatedAtMS: 2
                )
            )
        ],
        unresolvedPriorWeekCount: 2,
        leadInsight: .previewCurrent,
        hasConfirmedInsightHistory: true
    )
}

extension InsightRecord {
    static let previewCurrent = InsightRecord(
        id: "50000000-0000-0000-0000-000000000001",
        body: "Your best planning sessions happen before midday.",
        status: .confirmed,
        isTimeSensitive: true,
        homeEligibleUntilMS: 1_900_000_000_000,
        createdAtMS: 1_799_712_000_000,
        updatedAtMS: 1_800_000_000_000
    )

    static let previewReview = InsightRecord(
        id: "50000000-0000-0000-0000-000000000002",
        body: "Studio work may be crowding out recovery time.",
        status: .reviewNeeded,
        isTimeSensitive: false,
        homeEligibleUntilMS: nil,
        createdAtMS: 1_790_000_000_000,
        updatedAtMS: 1_795_000_000_000
    )

    static let previewHistory = InsightRecord(
        id: "50000000-0000-0000-0000-000000000003",
        body: "Short daily sessions kept the garden plan moving.",
        status: .superseded,
        isTimeSensitive: false,
        homeEligibleUntilMS: nil,
        createdAtMS: 1_780_000_000_000,
        updatedAtMS: 1_785_000_000_000
    )
}

extension InsightsSnapshot {
    static let previewContent = InsightsSnapshot(
        current: [.previewCurrent],
        reviewNeeded: [.previewReview],
        history: [.previewHistory]
    )
}
