import Foundation
import TaisaStorage

public enum CareerWorkClientError: Error, Sendable { case mutationUnavailable }

public struct ActionDraft: Sendable, Equatable {
    public let title: String
    public let detail: String
    public let parent: ActionParentContext
    public let dueDay: ActionDueDay?
    public init(title: String, detail: String, parent: ActionParentContext, dueDay: ActionDueDay?) {
        self.title = title; self.detail = detail; self.parent = parent; self.dueDay = dueDay
    }
}

public struct CareerWorkClient: Sendable {
    public var loadOverview: @Sendable () async throws -> CareerWorkOverview
    public var loadMilestones: @Sendable () async throws -> [MilestoneRecord]
    public var loadDeletedActions: @Sendable () async throws -> [ActionRecord]
    public var loadActions: @Sendable (ActionCollectionFilter, ActionDueDay) async throws -> [ActionRecord]
    public var loadActionDetail: @Sendable (String) async throws -> ActionDetailSnapshot?
    public var reviewActionDuplicates: @Sendable (String, String?) async throws -> ActionDuplicateReview
    public var createCanonicalAction: @Sendable (ActionDraft) async throws -> ActionRecord
    public var addChecklistItem: @Sendable (String, String) async throws -> ActionChecklistItemRecord
    public var setChecklistItemCompleted: @Sendable (String, Bool) async throws -> ActionChecklistItemRecord
    public var completeAction: @Sendable (String, String) async throws -> ActionCompletionResult
    public var reopenAction: @Sendable (String) async throws -> ActionRecord
    public var undoMistakenCompletion: @Sendable (String, String) async throws -> ActionRecord
    public var editCanonicalAction: @Sendable (String, ActionDraft, Int64) async throws -> ActionRecord
    public var renameChecklistItem: @Sendable (String, String) async throws -> ActionChecklistItemRecord
    public var removeChecklistItem: @Sendable (String) async throws -> Void
    public var reorderChecklist: @Sendable (String, [String]) async throws -> Void
    public var promoteChecklistItem: @Sendable (String) async throws -> ActionChecklistPromotionResult
    public var dropAction: @Sendable (String) async throws -> ActionRecord
    public var deleteAction: @Sendable (String) async throws -> Void
    public var restoreAction: @Sendable (String) async throws -> ActionRecord
    public var loadGoal: @Sendable (String) async throws -> CareerGoalSnapshot?
    public var loadAction: @Sendable (String) async throws -> ActionRecord?
    public var loadEvidence: @Sendable (String) async throws -> EvidenceRecord?
    public var createGoal: @Sendable (String, String) async throws -> GoalRecord
    public var createMilestone: @Sendable (String, String, Int64?) async throws -> MilestoneRecord
    public var createAction: @Sendable (String, String, String, Int64?) async throws -> ActionRecord
    public var addEvidence: @Sendable (String, String?, String, String, Int64) async throws -> EvidenceRecord
    public var updateGoal: @Sendable (String, String, String) async throws -> Void
    public var transitionGoal: @Sendable (String, GoalStatus) async throws -> Void
    public var archiveGoal: @Sendable (String) async throws -> Void
    public var restoreGoal: @Sendable (String) async throws -> Void

    public init(
        loadOverview: @escaping @Sendable () async throws -> CareerWorkOverview,
        loadMilestones: @escaping @Sendable () async throws -> [MilestoneRecord] = { [] },
        loadDeletedActions: @escaping @Sendable () async throws -> [ActionRecord] = { [] },
        loadActions: @escaping @Sendable (ActionCollectionFilter, ActionDueDay) async throws -> [ActionRecord] = { _, _ in [] },
        loadActionDetail: @escaping @Sendable (String) async throws -> ActionDetailSnapshot? = { _ in nil },
        reviewActionDuplicates: @escaping @Sendable (String, String?) async throws -> ActionDuplicateReview = { _, _ in .init(candidates: []) },
        createCanonicalAction: @escaping @Sendable (ActionDraft) async throws -> ActionRecord = { _ in throw CareerWorkClientError.mutationUnavailable },
        addChecklistItem: @escaping @Sendable (String, String) async throws -> ActionChecklistItemRecord = { _, _ in throw CareerWorkClientError.mutationUnavailable },
        setChecklistItemCompleted: @escaping @Sendable (String, Bool) async throws -> ActionChecklistItemRecord = { _, _ in throw CareerWorkClientError.mutationUnavailable },
        completeAction: @escaping @Sendable (String, String) async throws -> ActionCompletionResult = { _, _ in throw CareerWorkClientError.mutationUnavailable },
        reopenAction: @escaping @Sendable (String) async throws -> ActionRecord = { _ in throw CareerWorkClientError.mutationUnavailable },
        undoMistakenCompletion: @escaping @Sendable (String, String) async throws -> ActionRecord = { _, _ in throw CareerWorkClientError.mutationUnavailable },
        editCanonicalAction: @escaping @Sendable (String, ActionDraft, Int64) async throws -> ActionRecord = { _, _, _ in throw CareerWorkClientError.mutationUnavailable },
        renameChecklistItem: @escaping @Sendable (String, String) async throws -> ActionChecklistItemRecord = { _, _ in throw CareerWorkClientError.mutationUnavailable },
        removeChecklistItem: @escaping @Sendable (String) async throws -> Void = { _ in throw CareerWorkClientError.mutationUnavailable },
        reorderChecklist: @escaping @Sendable (String, [String]) async throws -> Void = { _, _ in throw CareerWorkClientError.mutationUnavailable },
        promoteChecklistItem: @escaping @Sendable (String) async throws -> ActionChecklistPromotionResult = { _ in throw CareerWorkClientError.mutationUnavailable },
        dropAction: @escaping @Sendable (String) async throws -> ActionRecord = { _ in throw CareerWorkClientError.mutationUnavailable },
        deleteAction: @escaping @Sendable (String) async throws -> Void = { _ in throw CareerWorkClientError.mutationUnavailable },
        restoreAction: @escaping @Sendable (String) async throws -> ActionRecord = { _ in throw CareerWorkClientError.mutationUnavailable },
        loadGoal: @escaping @Sendable (String) async throws -> CareerGoalSnapshot? = { _ in nil },
        loadAction: @escaping @Sendable (String) async throws -> ActionRecord? = { _ in nil },
        loadEvidence: @escaping @Sendable (String) async throws -> EvidenceRecord? = { _ in nil },
        createGoal: @escaping @Sendable (String, String) async throws -> GoalRecord = { _, _ in throw CareerWorkClientError.mutationUnavailable },
        createMilestone: @escaping @Sendable (String, String, Int64?) async throws -> MilestoneRecord = { _, _, _ in throw CareerWorkClientError.mutationUnavailable },
        createAction: @escaping @Sendable (String, String, String, Int64?) async throws -> ActionRecord = { _, _, _, _ in throw CareerWorkClientError.mutationUnavailable },
        addEvidence: @escaping @Sendable (String, String?, String, String, Int64) async throws -> EvidenceRecord = { _, _, _, _, _ in throw CareerWorkClientError.mutationUnavailable },
        updateGoal: @escaping @Sendable (String, String, String) async throws -> Void = { _, _, _ in throw CareerWorkClientError.mutationUnavailable },
        transitionGoal: @escaping @Sendable (String, GoalStatus) async throws -> Void = { _, _ in throw CareerWorkClientError.mutationUnavailable },
        archiveGoal: @escaping @Sendable (String) async throws -> Void = { _ in throw CareerWorkClientError.mutationUnavailable },
        restoreGoal: @escaping @Sendable (String) async throws -> Void = { _ in throw CareerWorkClientError.mutationUnavailable }
    ) {
        self.loadOverview = loadOverview
        self.loadMilestones = loadMilestones
        self.loadDeletedActions = loadDeletedActions
        self.loadActions = loadActions
        self.loadActionDetail = loadActionDetail
        self.reviewActionDuplicates = reviewActionDuplicates
        self.createCanonicalAction = createCanonicalAction
        self.addChecklistItem = addChecklistItem
        self.setChecklistItemCompleted = setChecklistItemCompleted
        self.completeAction = completeAction
        self.reopenAction = reopenAction
        self.undoMistakenCompletion = undoMistakenCompletion
        self.editCanonicalAction = editCanonicalAction
        self.renameChecklistItem = renameChecklistItem
        self.removeChecklistItem = removeChecklistItem
        self.reorderChecklist = reorderChecklist
        self.promoteChecklistItem = promoteChecklistItem
        self.dropAction = dropAction
        self.deleteAction = deleteAction
        self.restoreAction = restoreAction
        self.loadGoal = loadGoal
        self.loadAction = loadAction
        self.loadEvidence = loadEvidence
        self.createGoal = createGoal
        self.createMilestone = createMilestone
        self.createAction = createAction
        self.addEvidence = addEvidence
        self.updateGoal = updateGoal
        self.transitionGoal = transitionGoal
        self.archiveGoal = archiveGoal
        self.restoreGoal = restoreGoal
    }
}

public extension CareerWorkClient {
    static func local(store: TaisaStore, deviceID: String, nowMS: @escaping @Sendable () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }) -> Self {
        let query = CareerWorkQuery(store: store)
        let commands = CareerWorkCommandRepository(store: store)
        let context: @Sendable () -> MutationContext = { .init(id: UUID().uuidString, deviceID: deviceID, timestamp: nowMS()) }
        return .init(
            loadOverview: { try await query.overview() },
            loadMilestones: { try await query.milestones() },
            loadDeletedActions: { try await query.deletedActions() },
            loadActions: { try await query.actions(filter: $0, localDay: $1) },
            loadActionDetail: { try await query.actionDetail(id: $0) },
            reviewActionDuplicates: { try await query.duplicateReview(title: $0, excludingActionID: $1) },
            createCanonicalAction: { draft in
                let goalID: String?, milestoneID: String?
                switch draft.parent {
                case .standalone: goalID = nil; milestoneID = nil
                case let .goal(id): goalID = id; milestoneID = nil
                case let .milestone(parentGoalID, parentMilestoneID): goalID = parentGoalID; milestoneID = parentMilestoneID
                }
                return try await commands.createAction(goalID: goalID, milestoneID: milestoneID, title: draft.title, detail: draft.detail, dueDay: draft.dueDay, context: context())
            },
            addChecklistItem: { try await commands.addChecklistItem(actionID: $0, title: $1, context: context()) },
            setChecklistItemCompleted: { try await commands.setChecklistItemCompleted(id: $0, completed: $1, context: context()) },
            completeAction: { try await commands.completeAction(id: $0, evidenceTitle: $1, context: context()) },
            reopenAction: { try await commands.reopenAction(id: $0, context: context()) },
            undoMistakenCompletion: { try await commands.undoMistakenCompletion(id: $0, completionEventID: $1, context: context()) },
            editCanonicalAction: { id, draft, expected in
                let goalID: String?, milestoneID: String?
                switch draft.parent {
                case .standalone: goalID = nil; milestoneID = nil
                case let .goal(parentID): goalID = parentID; milestoneID = nil
                case let .milestone(parentGoalID, parentMilestoneID): goalID = parentGoalID; milestoneID = parentMilestoneID
                }
                return try await commands.editAction(id: id, title: draft.title, detail: draft.detail, goalID: goalID, milestoneID: milestoneID, dueDay: draft.dueDay, expectedUpdatedAtMS: expected, context: context())
            },
            renameChecklistItem: { try await commands.renameChecklistItem(id: $0, title: $1, context: context()) },
            removeChecklistItem: { try await commands.removeChecklistItem(id: $0, context: context()) },
            reorderChecklist: { try await commands.reorderChecklist(actionID: $0, orderedIDs: $1, context: context()) },
            promoteChecklistItem: { try await commands.promoteChecklistItem(id: $0, context: context()) },
            dropAction: { try await commands.dropAction(id: $0, context: context()) },
            deleteAction: { try await commands.deleteAction(id: $0, context: context()) },
            restoreAction: { try await commands.restoreAction(id: $0, context: context()) },
            loadGoal: { try await query.goal(id: $0) },
            loadAction: { try await query.action(id: $0) },
            loadEvidence: { try await query.evidence(id: $0) },
            createGoal: { try await commands.createGoal(title: $0, detail: $1, context: context()) },
            createMilestone: { try await commands.createMilestone(goalID: $0, title: $1, targetAtMS: $2, context: context()) },
            createAction: { try await commands.createAction(goalID: $0, title: $1, detail: $2, dueAtMS: $3, context: context()) },
            addEvidence: { try await commands.addEvidence(goalID: $0, actionID: $1, title: $2, detail: $3, occurredAtMS: $4, origin: .user, originID: nil, context: context()) },
            updateGoal: { try await commands.updateGoal(id: $0, title: $1, detail: $2, context: context()) },
            transitionGoal: { _ = try await commands.transitionGoal(id: $0, to: $1, source: .user, context: context()) },
            archiveGoal: { try await commands.archiveGoal(id: $0, context: context()) },
            restoreGoal: { try await commands.restoreGoal(id: $0, context: context()) }
        )
    }
}
