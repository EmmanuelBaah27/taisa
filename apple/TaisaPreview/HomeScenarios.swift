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
        scenario("home.refreshing", "Home refreshing", .adaptive, mode: .refreshing),
        scenario("home.failure", "Home failure", .adaptive, mode: .failure),
        scenario(
            "home.accessibilityText",
            "Home accessibility text",
            .phone,
            accessibility: .init(contentSize: .accessibilityExtraExtraExtraLarge),
            mode: .content
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

enum HomeScenarioMode: Sendable {
    case loading
    case empty
    case content
    case refreshing
    case failure
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
}
