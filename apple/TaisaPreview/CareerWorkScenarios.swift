import SwiftUI
import TaisaCareerWork
import TaisaPreviewSupport
import TaisaStorage

@MainActor
enum CareerWorkScenarios {
    static let scenarios: [PreviewScenario] = [
        scenario("actions.empty", "Actions empty", .phone, root: .actions, state: .empty),
        scenario("goals.content", "Goals content", .adaptive, root: .goals, state: .content(.preview, isRefreshing: false, issue: nil)),
        scenario("actions.action", "Action detail", .adaptive, root: .actions, state: .content(.actionPreview, isRefreshing: false, issue: nil), route: .action(id: ActionRecord.preview.id)),
        scenario("actions.failure", "Actions denied network", .phone, root: .actions, state: .failure(.storageUnavailable)),
        scenario("actions.recovery", "Actions recovery", .phone, root: .actions, state: .failure(.recoveryRequired)),
        scenario(
            "goals.accessibilityText",
            "Goals accessibility text",
            .phone,
            accessibility: .init(contentSize: .accessibilityExtraExtraExtraLarge),
            root: .goals,
            state: .content(.preview, isRefreshing: false, issue: nil)
        ),
        scenario(
            "actions.actionAccessibilityText",
            "Action detail accessibility text",
            .phone,
            accessibility: .init(contentSize: .accessibilityExtraExtraExtraLarge),
            root: .actions,
            state: .content(.actionPreview, isRefreshing: false, issue: nil),
            route: .action(id: ActionRecord.preview.id)
        ),
        scenario("goals.narrowIPad", "Goals narrow iPad", .tablet, root: .goals, state: .content(.preview, isRefreshing: false, issue: nil)),
        PreviewScenario(identifier: "goals.proposal", title: "Goal proposal", deviceFamily: .phone, accessibility: .default, readiness: .ready) {
            AnyView(NavigationStack {
                CareerWorkProposalReviewView(
                    title: "Add a portfolio milestone",
                    exactChange: "Create milestone “Publish three case studies” under “Move into product leadership”.",
                    source: "Coaching conversation",
                    accept: {}, correct: {}, reject: {}
                )
            })
        },
    ]

    private enum Root { case actions, goals }

    private static func scenario(
        _ identifier: String,
        _ title: String,
        _ family: PreviewDeviceFamily,
        accessibility: PreviewAccessibilitySettings = .default,
        root: Root,
        state: CareerWorkState,
        route: CareerWorkRoute? = nil
    ) -> PreviewScenario {
        PreviewScenario(identifier: identifier, title: title, deviceFamily: family, accessibility: accessibility, readiness: .ready) {
            let model = CareerWorkModel(client: .preview, initialState: state, route: route ?? .overview)
            switch root {
            case .actions: return AnyView(ActionsView(model: model, initialRoute: route))
            case .goals: return AnyView(GoalsView(model: model, initialRoute: route))
            }
        }
    }
}

private extension CareerWorkClient {
    static let preview = CareerWorkClient(
        loadOverview: { .preview },
        loadActions: { _, _ in [.preview] },
        loadActionDetail: { $0 == ActionRecord.preview.id ? .preview : nil }
    )
}

private extension CareerWorkOverview {
    static let preview = CareerWorkOverview(active: [.preview], paused: [], completed: [], archived: [])
}

private extension GoalRecord {
    static let preview = GoalRecord(
        id: "career-goal-preview",
        title: "Move into product leadership",
        detail: "Build visible evidence of strategic product work.",
        status: GoalStatus.active.rawValue,
        createdAtMS: 1_800_000_000_000,
        updatedAtMS: 1_800_000_000_000
    )
}

private extension CareerWorkProductSnapshot {
    static let preview = CareerWorkProductSnapshot(
        overview: .preview,
        selectedGoal: CareerGoalSnapshot(
            goal: .preview,
            milestones: [
                MilestoneRecord(id: "career-milestone-preview", goalID: GoalRecord.preview.id, title: "Publish three case studies", status: "open", targetAtMS: 1_820_000_000_000, updatedAtMS: 1_800_000_000_000)
            ],
            actions: [
                ActionRecord(id: "career-action-preview", goalID: GoalRecord.preview.id, title: "Outline first case study", detail: "Choose a launch with measurable impact.", status: ActionStatus.open.rawValue, dueAtMS: 1_810_000_000_000, createdAtMS: 1_800_000_000_000, updatedAtMS: 1_800_000_000_000)
            ],
            evidence: [
                EvidenceRecord(id: "career-evidence-preview", goalID: GoalRecord.preview.id, actionID: nil, title: "Led roadmap review", detail: "Aligned design and engineering on the next-quarter trade-offs.", occurredAtMS: 1_800_000_000_000, createdAtMS: 1_800_000_000_000)
            ],
            provenance: [
                EvidenceProvenance(evidenceID: "career-evidence-preview", origin: .user, originID: nil, supersedesEvidenceID: nil)
            ],
            progress: CareerWorkProgress(summary: "0 of 1 milestones and 0 of 1 actions completed; 1 evidence item recorded.", completedMilestones: 0, milestoneCount: 1, completedActions: 0, actionCount: 1, evidenceCount: 1)
        )
    )

    static let actionPreview = CareerWorkProductSnapshot(
        overview: .preview,
        actions: [.preview],
        selectedGoal: nil,
        selectedAction: .preview,
        selectedActionDetail: .preview
    )
}

private extension ActionRecord {
    static let preview = ActionRecord(
        id: "career-action-preview",
        goalID: GoalRecord.preview.id,
        title: "Outline first case study",
        detail: "Choose a launch with measurable impact.",
        status: ActionStatus.active.rawValue,
        dueAtMS: nil,
        createdAtMS: 1_800_000_000_000,
        updatedAtMS: 1_800_000_000_000,
        dueDay: ActionDueDay(rawValue: "2027-01-15")
    )
}

private extension ActionDetailSnapshot {
    static let preview = ActionDetailSnapshot(
        action: .preview,
        goal: .preview,
        milestone: nil,
        checklist: [
            .init(id: "checklist-one", actionID: ActionRecord.preview.id, title: "Choose the launch", state: .completed, position: 0, promotedActionID: nil, createdAtMS: 1_800_000_000_000, updatedAtMS: 1_800_000_000_000),
            .init(id: "checklist-two", actionID: ActionRecord.preview.id, title: "Collect impact numbers", state: .pending, position: 1, promotedActionID: nil, createdAtMS: 1_800_000_000_000, updatedAtMS: 1_800_000_000_000),
        ],
        events: [
            .init(id: "event-one", actionID: ActionRecord.preview.id, kind: .created, fromStatus: nil, toStatus: .active, detail: nil, source: .user, sourceID: nil, occurredAtMS: 1_800_000_000_000),
        ],
        currentEvidence: [
            .init(id: "evidence-one", goalID: GoalRecord.preview.id, actionID: ActionRecord.preview.id, title: "Launch metrics collected", detail: "Activation improved by twelve percent.", occurredAtMS: 1_800_000_000_000, createdAtMS: 1_800_000_000_000),
        ],
        supersededEvidence: [],
        placement: nil
    )
}
