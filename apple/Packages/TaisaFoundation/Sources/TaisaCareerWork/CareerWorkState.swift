import TaisaStorage

public enum CareerWorkIssue: Sendable, Equatable {
    case storageUnavailable
    case recoveryRequired
    case conflict
    case invalidInput
}

public struct CareerWorkProductSnapshot: Sendable, Equatable {
    public let overview: CareerWorkOverview
    public let actions: [ActionRecord]
    public let selectedGoal: CareerGoalSnapshot?
    public let selectedAction: ActionRecord?
    public let selectedActionDetail: ActionDetailSnapshot?
    public let selectedEvidence: EvidenceRecord?

    public init(overview: CareerWorkOverview, actions: [ActionRecord] = [], selectedGoal: CareerGoalSnapshot?, selectedAction: ActionRecord? = nil, selectedActionDetail: ActionDetailSnapshot? = nil, selectedEvidence: EvidenceRecord? = nil) {
        self.overview = overview
        self.actions = actions
        self.selectedGoal = selectedGoal
        self.selectedAction = selectedAction
        self.selectedActionDetail = selectedActionDetail
        self.selectedEvidence = selectedEvidence
    }

    public var isEmpty: Bool {
        overview.active.isEmpty && overview.paused.isEmpty && overview.completed.isEmpty && overview.archived.isEmpty && actions.isEmpty
    }
}

public enum CareerWorkState: Sendable, Equatable {
    case idle
    case loading
    case empty
    case content(CareerWorkProductSnapshot, isRefreshing: Bool, issue: CareerWorkIssue?)
    case failure(CareerWorkIssue)

    public var snapshot: CareerWorkProductSnapshot? {
        guard case let .content(snapshot, _, _) = self else { return nil }
        return snapshot
    }

    public var issue: CareerWorkIssue? {
        switch self {
        case let .content(_, _, issue): issue
        case let .failure(issue): issue
        default: nil
        }
    }
}
