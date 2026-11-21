import Foundation
import Observation
import TaisaStorage

@MainActor
@Observable
public final class CareerWorkModel {
    public private(set) var state: CareerWorkState
    public private(set) var route: CareerWorkRoute
    public private(set) var duplicateGate: ActionDuplicateReview?
    public private(set) var actionFilter: ActionCollectionFilter

    @ObservationIgnored private let client: CareerWorkClient
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var loadTask: Task<LoadOutcome, Never>?
    @ObservationIgnored private var pendingActionDraft: ActionDraft?
    @ObservationIgnored private let localDay: @Sendable () -> ActionDueDay

    public init(client: CareerWorkClient, initialState: CareerWorkState = .idle, route: CareerWorkRoute = .overview, actionFilter: ActionCollectionFilter = .init(lifecycle: .active), localDay: @escaping @Sendable () -> ActionDueDay = currentLocalActionDay) {
        self.client = client
        self.state = initialState
        self.route = route
        duplicateGate = nil
        self.actionFilter = actionFilter
        self.localDay = localDay
    }

    public func load() async {
        generation += 1
        let active = generation
        let retained = state.snapshot
        loadTask?.cancel()
        state = retained.map { .content($0, isRefreshing: true, issue: nil) } ?? .loading
        let client = client
        let route = route
        let filter = actionFilter
        let day = localDay()
        let task = Task<LoadOutcome, Never> {
            do {
                async let overview = client.loadOverview()
                async let actions = client.loadActions(filter, day)
                async let milestones = client.loadMilestones()
                async let deletedActions = client.loadDeletedActions()
                let detail: CareerGoalSnapshot?
                let action: ActionRecord?
                let actionDetail: ActionDetailSnapshot?
                let evidence: EvidenceRecord?
                switch route {
                case let .goal(id):
                    detail = try await client.loadGoal(id); action = nil; actionDetail = nil; evidence = nil
                case let .action(id):
                    detail = nil
                    actionDetail = try await client.loadActionDetail(id)
                    action = if let loaded = actionDetail?.action { loaded } else { try await client.loadAction(id) }
                    evidence = nil
                case let .evidence(id):
                    detail = nil; action = nil; actionDetail = nil; evidence = try await client.loadEvidence(id)
                case .overview:
                    detail = nil; action = nil; actionDetail = nil; evidence = nil
                }
                let snapshot = try await CareerWorkProductSnapshot(overview: overview, actions: actions, milestones: milestones, deletedActions: deletedActions, selectedGoal: detail, selectedAction: action, selectedActionDetail: actionDetail, selectedEvidence: evidence)
                try Task.checkCancellation()
                return .success(snapshot)
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .failure(Self.issue(for: error))
            }
        }
        loadTask = task
        let outcome = await task.value
        guard generation == active else { return }
        loadTask = nil
        switch outcome {
        case let .success(snapshot): state = snapshot.isEmpty ? .empty : .content(snapshot, isRefreshing: false, issue: nil)
        case let .failure(issue): state = retained.map { .content($0, isRefreshing: false, issue: issue) } ?? .failure(issue)
        case .cancelled: state = retained.map { .content($0, isRefreshing: false, issue: nil) } ?? .idle
        }
    }

    public func retry() async { await load() }

    public func select(_ route: CareerWorkRoute) async {
        self.route = route
        await load()
    }

    public func setActionFilter(_ filter: ActionCollectionFilter) async {
        actionFilter = filter
        await load()
    }

    public func createGoal(title: String, detail: String) async {
        await mutate {
            let goal = try await client.createGoal(title, detail)
            route = .goal(id: goal.id)
        }
    }

    public func updateSelectedGoal(title: String, detail: String) async {
        guard case let .goal(id) = route else { return }
        await mutate { try await client.updateGoal(id, title, detail) }
    }

    public func createMilestone(title: String, targetAtMS: Int64?) async {
        guard case let .goal(id) = route else { return }
        await mutate { _ = try await client.createMilestone(id, title, targetAtMS) }
    }

    public func createAction(title: String, detail: String, dueAtMS: Int64?) async {
        guard case let .goal(id) = route else { return }
        await mutate { _ = try await client.createAction(id, title, detail, dueAtMS) }
    }

    public func createAction(_ draft: ActionDraft) async {
        do {
            let title = try CareerWorkTitle.validating(draft.title).value
            let validated = ActionDraft(title: title, detail: draft.detail, parent: draft.parent, dueDay: draft.dueDay)
            let review = try await client.reviewActionDuplicates(title, nil)
            if !review.candidates.isEmpty {
                pendingActionDraft = validated
                duplicateGate = review
                return
            }
            await createValidatedAction(validated)
        } catch {
            publish(error)
        }
    }

    public func resolveDuplicate(_ decision: ActionDuplicateDecision) async {
        guard let draft = pendingActionDraft else { return }
        switch decision {
        case .openExisting:
            if let existing = duplicateGate?.candidates.first { route = .action(id: existing.id) }
            pendingActionDraft = nil; duplicateGate = nil
            await load()
        case .createSeparate:
            pendingActionDraft = nil; duplicateGate = nil
            await createValidatedAction(draft)
        }
    }

    public func cancelDuplicateReview() {
        pendingActionDraft = nil
        duplicateGate = nil
    }

    public func editSelectedAction(_ draft: ActionDraft, expectedUpdatedAtMS: Int64) async {
        guard case let .action(id) = route else { return }
        await mutate { _ = try await client.editCanonicalAction(id, draft, expectedUpdatedAtMS) }
    }

    public func addChecklistItem(title: String) async {
        guard case let .action(id) = route else { return }
        await mutate { _ = try await client.addChecklistItem(id, title) }
    }

    public func setChecklistItemCompleted(id: String, completed: Bool) async {
        await mutate { _ = try await client.setChecklistItemCompleted(id, completed) }
    }

    public func renameChecklistItem(id: String, title: String) async {
        await mutate { _ = try await client.renameChecklistItem(id, title) }
    }

    public func removeChecklistItem(id: String) async {
        await mutate { try await client.removeChecklistItem(id) }
    }

    public func reorderChecklist(_ orderedIDs: [String]) async {
        guard case let .action(id) = route else { return }
        await mutate { try await client.reorderChecklist(id, orderedIDs) }
    }

    public func promoteChecklistItem(id: String) async {
        await mutate { _ = try await client.promoteChecklistItem(id) }
    }

    public func completeSelectedAction(evidenceTitle: String) async {
        guard case let .action(id) = route else { return }
        await mutate { _ = try await client.completeAction(id, evidenceTitle) }
    }

    public func dropSelectedAction() async {
        guard case let .action(id) = route else { return }
        await mutate { _ = try await client.dropAction(id) }
    }

    public func reopenSelectedAction() async {
        guard case let .action(id) = route else { return }
        await mutate { _ = try await client.reopenAction(id) }
    }

    public func correctSelectedCompletion(eventID: String) async {
        guard case let .action(id) = route else { return }
        await mutate { _ = try await client.undoMistakenCompletion(id, eventID) }
    }

    public func deleteSelectedAction() async {
        guard case let .action(id) = route else { return }
        await mutate {
            try await client.deleteAction(id)
            route = .overview
        }
    }

    public func restoreAction(id: String) async {
        await mutate {
            _ = try await client.restoreAction(id)
            route = .action(id: id)
        }
    }

    public func addEvidence(actionID: String?, title: String, detail: String, occurredAtMS: Int64) async {
        guard case let .goal(id) = route else { return }
        await mutate { _ = try await client.addEvidence(id, actionID, title, detail, occurredAtMS) }
    }

    public func transitionSelectedGoal(to status: GoalStatus) async {
        guard case let .goal(id) = route else { return }
        await mutate { try await client.transitionGoal(id, status) }
    }

    public func archiveSelectedGoal() async {
        guard case let .goal(id) = route else { return }
        await mutate { try await client.archiveGoal(id) }
    }

    public func restoreSelectedGoal() async {
        guard case let .goal(id) = route else { return }
        await mutate { try await client.restoreGoal(id) }
    }

    private func mutate(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            await load()
        } catch {
            let issue = Self.issue(for: error)
            state = state.snapshot.map { .content($0, isRefreshing: false, issue: issue) } ?? .failure(issue)
        }
    }

    private func createValidatedAction(_ draft: ActionDraft) async {
        await mutate {
            let action = try await client.createCanonicalAction(draft)
            route = .action(id: action.id)
        }
    }

    private func publish(_ error: any Error) {
        let issue = Self.issue(for: error)
        state = state.snapshot.map { .content($0, isRefreshing: false, issue: issue) } ?? .failure(issue)
    }

    private static func issue(for error: any Error) -> CareerWorkIssue {
        if error is CareerWorkProposalError { return .conflict }
        if let contract = error as? CareerWorkContractError { return contract == .staleTarget ? .conflict : .invalidInput }
        guard let storage = error as? StorageError else { return .storageUnavailable }
        switch storage {
        case .missingKeyForExistingStore, .authenticationFailed, .integrityFailed, .schemaMismatch, .unsupportedMigration, .unsupportedSchemaVersion:
            return .recoveryRequired
        default:
            return .storageUnavailable
        }
    }
}

@usableFromInline
internal func currentLocalActionDay() -> ActionDueDay {
    let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    let value = String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    return ActionDueDay(rawValue: value)!
}

private enum LoadOutcome: Sendable {
    case success(CareerWorkProductSnapshot)
    case failure(CareerWorkIssue)
    case cancelled
}
