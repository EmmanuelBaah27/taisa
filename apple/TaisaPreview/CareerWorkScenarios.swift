import SwiftUI
import TaisaCareerWork
import TaisaPreviewSupport
import TaisaStorage

@MainActor
enum CareerWorkScenarios {
    static let scenarios: [PreviewScenario] = [
        scenario("career.empty", "Career Work empty", .phone, state: .empty),
        scenario("career.content", "Career Work content", .adaptive, state: .content(.preview, isRefreshing: false, issue: nil)),
        scenario("career.failure", "Career Work denied network", .phone, state: .failure(.storageUnavailable)),
        scenario("career.recovery", "Career Work recovery", .phone, state: .failure(.recoveryRequired)),
        scenario(
            "career.accessibilityText",
            "Career Work accessibility text",
            .phone,
            accessibility: .init(contentSize: .accessibilityExtraExtraExtraLarge),
            state: .content(.preview, isRefreshing: false, issue: nil)
        ),
        scenario("career.narrowIPad", "Career Work narrow iPad", .tablet, state: .content(.preview, isRefreshing: false, issue: nil)),
        PreviewScenario(identifier: "career.proposal", title: "Career Work proposal", deviceFamily: .phone, accessibility: .default, readiness: .ready) {
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

    private static func scenario(
        _ identifier: String,
        _ title: String,
        _ family: PreviewDeviceFamily,
        accessibility: PreviewAccessibilitySettings = .default,
        state: CareerWorkState
    ) -> PreviewScenario {
        PreviewScenario(identifier: identifier, title: title, deviceFamily: family, accessibility: accessibility, readiness: .ready) {
            AnyView(CareerWorkView(model: CareerWorkModel(client: .preview, initialState: state)))
        }
    }
}

private extension CareerWorkClient {
    static let preview = CareerWorkClient(loadOverview: { .preview })
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
}
