import Testing
@testable import TaisaStorage

@Suite struct CareerWorkContractTests {
    @Test func goalLifecycleAllowsOnlyDeliberateTransitions() {
        #expect(GoalStatus.active.canTransition(to: .paused))
        #expect(GoalStatus.active.canTransition(to: .completed))
        #expect(GoalStatus.paused.canTransition(to: .active))
        #expect(GoalStatus.completed.canTransition(to: .active))
        #expect(!GoalStatus.paused.canTransition(to: .completed))
        #expect(!GoalStatus.active.canTransition(to: .active))
    }

    @Test func milestoneAndActionLifecycleSupportCompletionAndReopen() {
        #expect(MilestoneStatus.planned.storageValue == "open")
        #expect(MilestoneStatus.planned.canTransition(to: .completed))
        #expect(MilestoneStatus.completed.canTransition(to: .planned))
        #expect(ActionStatus.open.canTransition(to: .completed))
        #expect(ActionStatus.completed.canTransition(to: .open))
        #expect(!ActionStatus.completed.canTransition(to: .completed))
    }

    @Test func titlesAreTrimmedAndEmptyTitlesFailWithoutEchoingContent() throws {
        #expect(try CareerWorkTitle.validating("  Grow into staff scope  ").value == "Grow into staff scope")
        #expect(throws: CareerWorkContractError.invalidTitle) {
            try CareerWorkTitle.validating(" \n\t ")
        }
        #expect(CareerWorkContractError.invalidTitle.diagnosticCode == "career_work_invalid_title")
        #expect(CareerWorkContractError.invalidTransition.diagnosticCode == "career_work_invalid_transition")
    }

    @Test func evidenceOriginsAndProposalDecisionsMatchPersistedContracts() {
        #expect(EvidenceOrigin.allCases.map(\.rawValue) == ["user", "action", "conversation", "import"])
        #expect(ProposalDecision.allCases.map(\.rawValue) == ["accepted", "corrected", "rejected", "undone"])
    }

    @Test func stableRoutesKeepEntityIdentity() {
        #expect(CareerWorkRoute.goal(id: "goal-1").stableID == "goal:goal-1")
        #expect(CareerWorkRoute.action(id: "action-1").stableID == "action:action-1")
        #expect(CareerWorkRoute.evidence(id: "evidence-1").stableID == "evidence:evidence-1")
        #expect(CareerWorkRoute.overview.stableID == "overview")
    }
}
