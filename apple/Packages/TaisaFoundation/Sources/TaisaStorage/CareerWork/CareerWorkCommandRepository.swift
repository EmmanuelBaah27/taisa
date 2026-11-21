import Foundation
import GRDB

public struct ActionCompletionResult: Sendable, Equatable {
    public let action: ActionRecord
    public let evidence: EvidenceRecord
    public let event: ActionEventRecord

    public init(action: ActionRecord, evidence: EvidenceRecord, event: ActionEventRecord) {
        self.action = action
        self.evidence = evidence
        self.event = event
    }
}

public struct ActionChecklistPromotionResult: Sendable, Equatable {
    public let checklistItem: ActionChecklistItemRecord
    public let action: ActionRecord
}

enum CareerWorkCommandTestError: Error { case injectedFailure }

public struct CareerWorkCommandRepository: Sendable {
    private let store: TaisaStore
    private let failAfterPrimaryMutation: Bool

    public init(store: TaisaStore) {
        self.store = store
        failAfterPrimaryMutation = false
    }

    init(store: TaisaStore, failAfterPrimaryMutation: Bool) {
        self.store = store
        self.failAfterPrimaryMutation = failAfterPrimaryMutation
    }

    public func createGoal(id: String = UUID().uuidString, title: String, detail: String, source: CareerWorkMutationSource = .user, sourceID: String? = nil, context: MutationContext) async throws -> GoalRecord {
        let title = try CareerWorkTitle.validating(title).value
        let record = GoalRecord(id: id, title: title, detail: detail, status: GoalStatus.active.rawValue, createdAtMS: context.timestamp, updatedAtMS: context.timestamp)
        try await store.write { db in
            try Self.goalCore(self.store).create(record, context: context, db: db)
            try Self.insertEvent(entity: "goal", id: record.id, transition: "created", from: nil, to: record.status, source: source, sourceID: sourceID, context: context, db: db)
        }
        return record
    }

    public func updateGoal(id: String, title: String, detail: String, context: MutationContext) async throws {
        let title = try CareerWorkTitle.validating(title).value
        try await store.write { db in
            guard let current = try Self.fetchGoal(id: id, db: db) else { throw RepositoryError.notFound }
            let updated = GoalRecord(id: current.id, title: title, detail: detail, status: current.status, createdAtMS: current.createdAtMS, updatedAtMS: context.timestamp)
            try Self.goalCore(self.store).update(updated, context: context, db: db)
        }
    }

    public func createMilestone(id: String = UUID().uuidString, goalID: String, title: String, targetAtMS: Int64?, source: CareerWorkMutationSource = .user, sourceID: String? = nil, context: MutationContext) async throws -> MilestoneRecord {
        let title = try CareerWorkTitle.validating(title).value
        let record = MilestoneRecord(id: id, goalID: goalID, title: title, status: MilestoneStatus.planned.storageValue, targetAtMS: targetAtMS, updatedAtMS: context.timestamp)
        try await store.write { db in
            try Self.milestoneCore(self.store).create(record, context: context, db: db)
            try Self.insertEvent(entity: "milestone", id: record.id, transition: "created", from: nil, to: record.status, source: source, sourceID: sourceID, context: context, db: db)
        }
        return record
    }

    public func createAction(id: String = UUID().uuidString, goalID: String?, title: String, detail: String, dueAtMS: Int64?, source: CareerWorkMutationSource = .user, sourceID: String? = nil, context: MutationContext) async throws -> ActionRecord {
        let title = try CareerWorkTitle.validating(title).value
        let record = ActionRecord(id: id, goalID: goalID, title: title, detail: detail, status: ActionStatus.open.rawValue, dueAtMS: dueAtMS, createdAtMS: context.timestamp, updatedAtMS: context.timestamp)
        try await store.write { db in
            try Self.actionCore(self.store).create(record, context: context, db: db)
            try Self.insertEvent(entity: "action", id: record.id, transition: "created", from: nil, to: record.status, source: source, sourceID: sourceID, context: context, db: db)
        }
        return record
    }

    public func createAction(
        id: String = UUID().uuidString,
        goalID: String?,
        milestoneID: String?,
        title: String,
        detail: String,
        dueDay: ActionDueDay?,
        context: MutationContext
    ) async throws -> ActionRecord {
        let title = try CareerWorkTitle.validating(title).value
        return try await store.write { db in
            let resolvedGoalID: String?
            if let milestoneID {
                guard let milestone = try Self.fetchMilestone(id: milestoneID, db: db) else {
                    throw CareerWorkContractError.invalidRelationship
                }
                guard goalID == nil || goalID?.caseInsensitiveCompare(milestone.goalID) == .orderedSame else {
                    throw CareerWorkContractError.invalidRelationship
                }
                resolvedGoalID = milestone.goalID
            } else {
                resolvedGoalID = goalID
            }
            if let resolvedGoalID, try Self.fetchGoal(id: resolvedGoalID, db: db) == nil {
                throw CareerWorkContractError.invalidRelationship
            }
            let record = ActionRecord(
                id: id,
                goalID: resolvedGoalID,
                title: title,
                detail: detail,
                status: ActionStatus.active.rawValue,
                dueAtMS: nil,
                createdAtMS: context.timestamp,
                updatedAtMS: context.timestamp,
                milestoneID: milestoneID,
                dueDay: dueDay
            )
            try Self.actionCore(self.store).create(record, context: context, db: db)
            _ = try Self.insertActionEvent(
                actionID: record.id,
                kind: .created,
                from: nil,
                to: .active,
                source: .user,
                sourceID: context.id,
                context: context,
                db: db
            )
            return record
        }
    }

    public func completeAction(id: String, evidenceTitle: String, context: MutationContext) async throws -> ActionCompletionResult {
        let evidenceTitle = try CareerWorkTitle.validating(evidenceTitle).value
        return try await store.write { db in
            if let existing = try Self.existingCompletion(actionID: id, sourceID: context.id, db: db) { return existing }
            guard let current = try Self.fetchAction(id: id, db: db) else { throw RepositoryError.notFound }
            guard current.status == ActionStatus.active.rawValue else { throw CareerWorkContractError.invalidTransition }

            let completed = Self.copyAction(current, status: .completed, timestamp: context.timestamp)
            try Self.actionCore(self.store).update(completed, context: context, db: db)
            let event = try Self.insertActionEvent(
                actionID: id,
                kind: .completed,
                from: .active,
                to: .completed,
                source: .user,
                sourceID: context.id,
                context: context,
                db: db
            )
            try Self.removeActivePlacements(actionID: id, context: context, store: self.store, db: db)
            if failAfterPrimaryMutation { throw CareerWorkCommandTestError.injectedFailure }
            let evidence = EvidenceRecord(
                id: UUID().uuidString,
                goalID: current.goalID,
                actionID: current.id,
                title: evidenceTitle,
                detail: "",
                occurredAtMS: context.timestamp,
                createdAtMS: context.timestamp
            )
            let evidenceContext = MutationContext(id: UUID().uuidString, deviceID: context.deviceID, timestamp: context.timestamp)
            try Self.evidenceCore(self.store).create(evidence, context: evidenceContext, db: db)
            try db.execute(
                sql: "INSERT INTO evidence_provenance (evidence_id, origin_type, origin_id, supersedes_evidence_id, created_at_ms) VALUES (?, ?, ?, NULL, ?)",
                arguments: [evidence.id, EvidenceOrigin.action.rawValue, event.id, context.timestamp]
            )
            try db.execute(
                sql: "INSERT INTO action_evidence_links (evidence_id, completion_event_id, superseded_by_event_id) VALUES (?, ?, NULL)",
                arguments: [evidence.id, event.id]
            )
            return ActionCompletionResult(action: completed, evidence: evidence, event: event)
        }
    }

    public func reopenAction(id: String, context: MutationContext) async throws -> ActionRecord {
        try await store.write { db in
            guard let current = try Self.fetchAction(id: id, db: db),
                  let status = ActionStatus(rawValue: current.status),
                  status == .completed || status == .dropped else { throw CareerWorkContractError.invalidTransition }
            let reopened = Self.copyAction(current, status: .active, timestamp: context.timestamp)
            try Self.actionCore(self.store).update(reopened, context: context, db: db)
            _ = try Self.insertActionEvent(
                actionID: id,
                kind: .reopened,
                from: status,
                to: .active,
                source: .user,
                sourceID: context.id,
                context: context,
                db: db
            )
            return reopened
        }
    }

    public func undoMistakenCompletion(id: String, completionEventID: String, context: MutationContext) async throws -> ActionRecord {
        try await store.write { db in
            guard let current = try Self.fetchAction(id: id, db: db) else { throw RepositoryError.notFound }
            guard current.status == ActionStatus.completed.rawValue,
                  try Int.fetchOne(
                    db,
                    sql: "SELECT count(*) FROM action_events WHERE id = ? COLLATE NOCASE AND action_id = ? COLLATE NOCASE AND kind = 'completed'",
                    arguments: [completionEventID, id]
                  ) == 1,
                  try Int.fetchOne(
                    db,
                    sql: "SELECT count(*) FROM action_evidence_links WHERE completion_event_id = ? COLLATE NOCASE AND superseded_by_event_id IS NULL",
                    arguments: [completionEventID]
                  ) == 1 else { throw CareerWorkContractError.invalidTransition }

            let corrected = Self.copyAction(current, status: .active, timestamp: context.timestamp)
            try Self.actionCore(self.store).update(corrected, context: context, db: db)
            let correctionEvent = try Self.insertActionEvent(
                actionID: id,
                kind: .completionCorrected,
                from: .completed,
                to: .active,
                source: .undo,
                sourceID: completionEventID,
                context: context,
                db: db
            )
            try db.execute(
                sql: "UPDATE action_evidence_links SET superseded_by_event_id = ? WHERE completion_event_id = ? COLLATE NOCASE AND superseded_by_event_id IS NULL",
                arguments: [correctionEvent.id, completionEventID]
            )
            return corrected
        }
    }

    public func editAction(id: String, title: String, detail: String, goalID: String?, milestoneID: String?, dueDay: ActionDueDay?, expectedUpdatedAtMS: Int64, context: MutationContext) async throws -> ActionRecord {
        let title = try CareerWorkTitle.validating(title).value
        return try await store.write { db in
            guard let current = try Self.fetchAction(id: id, db: db) else { throw RepositoryError.notFound }
            guard current.updatedAtMS == expectedUpdatedAtMS else { throw CareerWorkContractError.staleTarget }
            let parent = try Self.resolvedGoalID(goalID: goalID, milestoneID: milestoneID, db: db)
            let updated = ActionRecord(id: id, goalID: parent, title: title, detail: detail, status: current.status, dueAtMS: current.dueAtMS, createdAtMS: current.createdAtMS, updatedAtMS: context.timestamp, milestoneID: milestoneID, dueDay: dueDay, origin: current.origin)
            try Self.actionCore(self.store).update(updated, context: context, db: db)
            _ = try Self.insertActionEvent(actionID: id, kind: (current.goalID != parent || current.milestoneID != milestoneID) ? .relationshipChanged : .edited, from: ActionStatus(rawValue: current.status), to: ActionStatus(rawValue: current.status), source: .user, sourceID: context.id, context: context, db: db)
            return updated
        }
    }

    public func addChecklistItem(actionID: String, title: String, context: MutationContext) async throws -> ActionChecklistItemRecord {
        let title = try CareerWorkTitle.validating(title).value
        return try await store.write { db in
            guard try Self.fetchAction(id: actionID, db: db) != nil else { throw RepositoryError.notFound }
            let position = (try Int.fetchOne(db, sql: "SELECT max(position) + 1 FROM action_checklist_items WHERE action_id = ?", arguments: [actionID])) ?? 0
            let item = ActionChecklistItemRecord(id: UUID().uuidString, actionID: actionID, title: title, state: .pending, position: position, promotedActionID: nil, createdAtMS: context.timestamp, updatedAtMS: context.timestamp)
            try Self.insertChecklistItem(item, db: db)
            _ = try Self.insertActionEvent(actionID: actionID, kind: .checklistChanged, from: nil, to: nil, source: .user, sourceID: context.id, context: context, db: db)
            return item
        }
    }

    public func setChecklistItemCompleted(id: String, completed: Bool, context: MutationContext) async throws -> ActionChecklistItemRecord {
        try await store.write { db in
            guard let current = try Self.fetchChecklistItem(id: id, db: db), current.state != .promoted else { throw CareerWorkContractError.invalidTransition }
            let item = ActionChecklistItemRecord(id: current.id, actionID: current.actionID, title: current.title, state: completed ? .completed : .pending, position: current.position, promotedActionID: nil, createdAtMS: current.createdAtMS, updatedAtMS: context.timestamp)
            try db.execute(sql: "UPDATE action_checklist_items SET state = ?, updated_at_ms = ? WHERE id = ?", arguments: [item.state.rawValue, context.timestamp, id])
            _ = try Self.insertActionEvent(actionID: item.actionID, kind: .checklistChanged, from: nil, to: nil, source: .user, sourceID: context.id, context: context, db: db)
            return item
        }
    }

    public func renameChecklistItem(id: String, title: String, context: MutationContext) async throws -> ActionChecklistItemRecord {
        let title = try CareerWorkTitle.validating(title).value
        return try await store.write { db in
            guard let current = try Self.fetchChecklistItem(id: id, db: db) else { throw RepositoryError.notFound }
            let renamed = ActionChecklistItemRecord(id: current.id, actionID: current.actionID, title: title, state: current.state, position: current.position, promotedActionID: current.promotedActionID, createdAtMS: current.createdAtMS, updatedAtMS: context.timestamp)
            try db.execute(sql: "UPDATE action_checklist_items SET title = ?, updated_at_ms = ? WHERE id = ?", arguments: [title, context.timestamp, id])
            _ = try Self.insertActionEvent(actionID: current.actionID, kind: .checklistChanged, from: nil, to: nil, source: .user, sourceID: context.id, context: context, db: db)
            return renamed
        }
    }

    public func removeChecklistItem(id: String, context: MutationContext) async throws {
        try await store.write { db in
            guard let current = try Self.fetchChecklistItem(id: id, db: db) else { throw RepositoryError.notFound }
            try db.execute(sql: "DELETE FROM action_checklist_items WHERE id = ?", arguments: [id])
            let later = try Row.fetchAll(db, sql: "SELECT id FROM action_checklist_items WHERE action_id = ? AND position > ? ORDER BY position", arguments: [current.actionID, current.position])
            for row in later { try db.execute(sql: "UPDATE action_checklist_items SET position = position - 1, updated_at_ms = ? WHERE id = ?", arguments: [context.timestamp, row["id"] as String]) }
            _ = try Self.insertActionEvent(actionID: current.actionID, kind: .checklistChanged, from: nil, to: nil, source: .user, sourceID: context.id, context: context, db: db)
        }
    }

    public func reorderChecklist(actionID: String, orderedIDs: [String], context: MutationContext) async throws {
        try await store.write { db in
            let stored = try String.fetchAll(db, sql: "SELECT id FROM action_checklist_items WHERE action_id = ?", arguments: [actionID])
            guard stored.count == orderedIDs.count, Set(stored.map { $0.lowercased() }) == Set(orderedIDs.map { $0.lowercased() }) else { throw CareerWorkContractError.invalidRelationship }
            try db.execute(sql: "UPDATE action_checklist_items SET position = position + 1000000 WHERE action_id = ?", arguments: [actionID])
            for (position, id) in orderedIDs.enumerated() { try db.execute(sql: "UPDATE action_checklist_items SET position = ?, updated_at_ms = ? WHERE id = ?", arguments: [position, context.timestamp, id]) }
            _ = try Self.insertActionEvent(actionID: actionID, kind: .checklistChanged, from: nil, to: nil, source: .user, sourceID: context.id, context: context, db: db)
        }
    }

    public func promoteChecklistItem(id: String, context: MutationContext) async throws -> ActionChecklistPromotionResult {
        try await store.write { db in
            guard let item = try Self.fetchChecklistItem(id: id, db: db), item.state != .promoted,
                  let parent = try Self.fetchAction(id: item.actionID, db: db) else { throw CareerWorkContractError.invalidTransition }
            let action = ActionRecord(id: UUID().uuidString, goalID: parent.goalID, title: item.title, detail: "", status: ActionStatus.active.rawValue, dueAtMS: nil, createdAtMS: context.timestamp, updatedAtMS: context.timestamp, milestoneID: parent.milestoneID, dueDay: nil)
            let childContext = MutationContext(id: UUID().uuidString, deviceID: context.deviceID, timestamp: context.timestamp)
            try Self.actionCore(self.store).create(action, context: childContext, db: db)
            let promoted = ActionChecklistItemRecord(id: item.id, actionID: item.actionID, title: item.title, state: .promoted, position: item.position, promotedActionID: action.id, createdAtMS: item.createdAtMS, updatedAtMS: context.timestamp)
            try db.execute(sql: "UPDATE action_checklist_items SET state = 'promoted', promoted_action_id = ?, updated_at_ms = ? WHERE id = ?", arguments: [action.id, context.timestamp, id])
            _ = try Self.insertActionEvent(actionID: parent.id, kind: .checklistPromoted, from: nil, to: nil, source: .user, sourceID: context.id, context: context, db: db)
            return ActionChecklistPromotionResult(checklistItem: promoted, action: action)
        }
    }

    public func dropAction(id: String, context: MutationContext) async throws -> ActionRecord {
        try await store.write { db in
            guard let current = try Self.fetchAction(id: id, db: db), current.status == ActionStatus.active.rawValue else { throw CareerWorkContractError.invalidTransition }
            let dropped = Self.copyAction(current, status: .dropped, timestamp: context.timestamp)
            try Self.actionCore(self.store).update(dropped, context: context, db: db)
            try Self.removeActivePlacements(actionID: id, context: context, store: self.store, db: db)
            _ = try Self.insertActionEvent(actionID: id, kind: .dropped, from: .active, to: .dropped, source: .user, sourceID: context.id, context: context, db: db)
            return dropped
        }
    }

    public func deleteAction(id: String, context: MutationContext) async throws {
        try await store.write { db in
            guard let current = try Self.fetchAction(id: id, db: db) else { throw RepositoryError.notFound }
            try Self.removeActivePlacements(actionID: id, context: context, store: self.store, db: db)
            _ = try Self.insertActionEvent(actionID: id, kind: .deleted, from: ActionStatus(rawValue: current.status), to: nil, source: .user, sourceID: context.id, context: context, db: db)
            try Self.actionCore(self.store).delete(id: id, context: context, db: db)
        }
    }

    public func restoreAction(id: String, context: MutationContext) async throws -> ActionRecord {
        try await store.write { db in
            guard let action = try Self.fetchAction(id: id, db: db),
                  try Int.fetchOne(db, sql: "SELECT count(*) FROM tombstones WHERE entity_type = 'action' AND entity_id = ? COLLATE NOCASE", arguments: [id]) == 1 else { throw RepositoryError.notFound }
            try db.execute(sql: "DELETE FROM tombstones WHERE entity_type = 'action' AND entity_id = ? COLLATE NOCASE", arguments: [id])
            _ = try Self.insertActionEvent(actionID: id, kind: .restored, from: ActionStatus(rawValue: action.status), to: ActionStatus(rawValue: action.status), source: .user, sourceID: context.id, context: context, db: db)
            return action
        }
    }

    public func addEvidence(goalID: String?, actionID: String?, title: String, detail: String, occurredAtMS: Int64, origin: EvidenceOrigin, originID: String?, context: MutationContext) async throws -> EvidenceRecord {
        guard goalID != nil || actionID != nil else { throw CareerWorkContractError.invalidRelationship }
        let title = try CareerWorkTitle.validating(title).value
        let record = EvidenceRecord(id: UUID().uuidString, goalID: goalID, actionID: actionID, title: title, detail: detail, occurredAtMS: occurredAtMS, createdAtMS: context.timestamp)
        try await store.write { db in
            try Self.evidenceCore(self.store).create(record, context: context, db: db)
            try db.execute(sql: "INSERT INTO evidence_provenance (evidence_id, origin_type, origin_id, supersedes_evidence_id, created_at_ms) VALUES (?, ?, ?, NULL, ?)", arguments: [record.id, origin.rawValue, originID, context.timestamp])
        }
        return record
    }

    public func correctEvidence(id: String, title: String, detail: String, occurredAtMS: Int64, origin: EvidenceOrigin, context: MutationContext) async throws -> EvidenceRecord {
        let title = try CareerWorkTitle.validating(title).value
        return try await store.write { db in
            guard let original = try Self.fetchEvidence(id: id, db: db) else { throw RepositoryError.notFound }
            let corrected = EvidenceRecord(id: UUID().uuidString, goalID: original.goalID, actionID: original.actionID, title: title, detail: detail, occurredAtMS: occurredAtMS, createdAtMS: context.timestamp)
            try Self.evidenceCore(self.store).create(corrected, context: context, db: db)
            try db.execute(sql: "INSERT INTO evidence_provenance (evidence_id, origin_type, origin_id, supersedes_evidence_id, created_at_ms) VALUES (?, ?, NULL, ?, ?)", arguments: [corrected.id, origin.rawValue, original.id, context.timestamp])
            return corrected
        }
    }

    public func transitionGoal(id: String, to next: GoalStatus, source: CareerWorkMutationSource, context: MutationContext) async throws -> GoalRecord {
        try await store.write { db in
            guard let current = try Self.fetchGoal(id: id, db: db), let status = GoalStatus(rawValue: current.status) else { throw RepositoryError.notFound }
            guard status.canTransition(to: next) else { throw CareerWorkContractError.invalidTransition }
            let updated = GoalRecord(id: current.id, title: current.title, detail: current.detail, status: next.rawValue, createdAtMS: current.createdAtMS, updatedAtMS: context.timestamp)
            try Self.goalCore(self.store).update(updated, context: context, db: db)
            let transition = next == .paused ? "paused" : (next == .completed ? "completed" : (status == .paused ? "resumed" : "reopened"))
            try Self.insertEvent(entity: "goal", id: id, transition: transition, from: status.rawValue, to: next.rawValue, source: source, context: context, db: db)
            return updated
        }
    }

    public func transitionMilestone(id: String, to next: MilestoneStatus, source: CareerWorkMutationSource, context: MutationContext) async throws -> MilestoneRecord {
        try await store.write { db in
            guard let current = try Self.fetchMilestone(id: id, db: db) else { throw RepositoryError.notFound }
            let status: MilestoneStatus = current.status == "open" ? .planned : .completed
            guard status.canTransition(to: next) else { throw CareerWorkContractError.invalidTransition }
            let updated = MilestoneRecord(id: current.id, goalID: current.goalID, title: current.title, status: next.storageValue, targetAtMS: current.targetAtMS, updatedAtMS: context.timestamp)
            try Self.milestoneCore(self.store).update(updated, context: context, db: db)
            try Self.insertEvent(entity: "milestone", id: id, transition: next == .completed ? "completed" : "reopened", from: current.status, to: updated.status, source: source, context: context, db: db)
            return updated
        }
    }

    public func transitionAction(id: String, to next: ActionStatus, source: CareerWorkMutationSource, context: MutationContext) async throws -> ActionRecord {
        try await store.write { db in
            guard let current = try Self.fetchAction(id: id, db: db), let status = ActionStatus(rawValue: current.status) else { throw RepositoryError.notFound }
            guard status.canTransition(to: next) else { throw CareerWorkContractError.invalidTransition }
            let updated = Self.copyAction(current, status: next, timestamp: context.timestamp)
            try Self.actionCore(self.store).update(updated, context: context, db: db)
            try Self.insertEvent(entity: "action", id: id, transition: next == .completed ? "completed" : "reopened", from: status.rawValue, to: next.rawValue, source: source, context: context, db: db)
            return updated
        }
    }

    public func archiveGoal(id: String, context: MutationContext) async throws {
        try await store.write { db in
            guard let goal = try Self.fetchGoal(id: id, db: db) else { throw RepositoryError.notFound }
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM career_work_archives WHERE entity_type = 'goal' AND entity_id = ? AND restored_at_ms IS NULL", arguments: [id]) == 0 else { throw CareerWorkContractError.invalidTransition }
            try db.execute(sql: "INSERT INTO career_work_archives (id, entity_type, entity_id, archived_at_ms) VALUES (?, 'goal', ?, ?)", arguments: [UUID().uuidString, id, context.timestamp])
            try Self.insertEvent(entity: "goal", id: id, transition: "archived", from: goal.status, to: goal.status, source: .user, context: context, db: db)
        }
    }

    public func restoreGoal(id: String, context: MutationContext) async throws {
        try await store.write { db in
            guard let goal = try Self.fetchGoal(id: id, db: db) else { throw RepositoryError.notFound }
            guard let archiveID = try String.fetchOne(db, sql: "SELECT id FROM career_work_archives WHERE entity_type = 'goal' AND entity_id = ? AND restored_at_ms IS NULL", arguments: [id]) else { throw CareerWorkContractError.invalidTransition }
            try db.execute(sql: "UPDATE career_work_archives SET restored_at_ms = ? WHERE id = ?", arguments: [context.timestamp, archiveID])
            try Self.insertEvent(entity: "goal", id: id, transition: "restored", from: goal.status, to: goal.status, source: .user, context: context, db: db)
        }
    }

    private static func insertEvent(entity: String, id: String, transition: String, from: String?, to: String, source: CareerWorkMutationSource, sourceID: String? = nil, context: MutationContext, db: Database) throws {
        try db.execute(sql: "INSERT INTO career_work_events (id, entity_type, entity_id, transition, from_status, to_status, source_type, source_id, occurred_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", arguments: [UUID().uuidString, entity, id, transition, from, to, source.rawValue, sourceID, context.timestamp])
    }

    private static func fetchGoal(id: String, db: Database) throws -> GoalRecord? { try Row.fetchOne(db, sql: "SELECT * FROM goals WHERE id = ? COLLATE NOCASE", arguments: [id]).map { GoalRecord(id: $0["id"], title: $0["title"], detail: $0["detail"], status: $0["status"], createdAtMS: $0["created_at_ms"], updatedAtMS: $0["updated_at_ms"]) } }
    private static func fetchMilestone(id: String, db: Database) throws -> MilestoneRecord? { try Row.fetchOne(db, sql: "SELECT * FROM milestones WHERE id = ? COLLATE NOCASE", arguments: [id]).map { MilestoneRecord(id: $0["id"], goalID: $0["goal_id"], title: $0["title"], status: $0["status"], targetAtMS: $0["target_at_ms"], updatedAtMS: $0["updated_at_ms"]) } }
    private static func fetchAction(id: String, db: Database) throws -> ActionRecord? { try Row.fetchOne(db, sql: "SELECT * FROM actions WHERE id = ? COLLATE NOCASE", arguments: [id]).map { row in
        ActionRecord(
            id: row["id"],
            goalID: row["goal_id"],
            title: row["title"],
            detail: row["detail"],
            status: row["status"],
            dueAtMS: row["due_at_ms"],
            createdAtMS: row["created_at_ms"],
            updatedAtMS: row["updated_at_ms"],
            milestoneID: row["milestone_id"],
            dueDay: (row["due_day"] as String?).flatMap(ActionDueDay.init(rawValue:)),
            origin: ActionOrigin(rawValue: row["origin"] as String) ?? .manual
        )
    } }
    private static func fetchEvidence(id: String, db: Database) throws -> EvidenceRecord? { try Row.fetchOne(db, sql: "SELECT * FROM evidence WHERE id = ? COLLATE NOCASE", arguments: [id]).map { EvidenceRecord(id: $0["id"], goalID: $0["goal_id"], actionID: $0["action_id"], title: $0["title"], detail: $0["detail"], occurredAtMS: $0["occurred_at_ms"], createdAtMS: $0["created_at_ms"]) } }

    private static func fetchChecklistItem(id: String, db: Database) throws -> ActionChecklistItemRecord? {
        try Row.fetchOne(db, sql: "SELECT * FROM action_checklist_items WHERE id = ? COLLATE NOCASE", arguments: [id]).map {
            ActionChecklistItemRecord(id: $0["id"], actionID: $0["action_id"], title: $0["title"], state: ActionChecklistState(rawValue: $0["state"])!, position: $0["position"], promotedActionID: $0["promoted_action_id"], createdAtMS: $0["created_at_ms"], updatedAtMS: $0["updated_at_ms"])
        }
    }

    private static func insertChecklistItem(_ item: ActionChecklistItemRecord, db: Database) throws {
        try db.execute(sql: "INSERT INTO action_checklist_items (id, action_id, title, state, position, promoted_action_id, created_at_ms, updated_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", arguments: [item.id, item.actionID, item.title, item.state.rawValue, item.position, item.promotedActionID, item.createdAtMS, item.updatedAtMS])
    }

    private static func resolvedGoalID(goalID: String?, milestoneID: String?, db: Database) throws -> String? {
        if let milestoneID {
            guard let milestone = try fetchMilestone(id: milestoneID, db: db), goalID == nil || goalID?.caseInsensitiveCompare(milestone.goalID) == .orderedSame else { throw CareerWorkContractError.invalidRelationship }
            return milestone.goalID
        }
        if let goalID, try fetchGoal(id: goalID, db: db) == nil { throw CareerWorkContractError.invalidRelationship }
        return goalID
    }

    private static func removeActivePlacements(actionID: String, context: MutationContext, store: TaisaStore, db: Database) throws {
        let ids = try String.fetchAll(db, sql: "SELECT p.id FROM weekly_placements p WHERE p.action_id = ? AND NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'weekly_placement' AND t.entity_id = p.id)", arguments: [actionID])
        for id in ids {
            let childContext = AssistantResponseRepository.childContext(context, entity: "weekly_placement", id: id)
            try RepositoryCore<WeeklyPlacementRecord>(store: store, spec: .init(table: "weekly_placements", entity: "weekly_placement", fields: [("id", "id"), ("actionID", "action_id"), ("weekStartMS", "week_start_ms"), ("plannedDayMS", "planned_day_ms"), ("createdAtMS", "created_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["actionID", "createdAtMS"], appendOnly: false)).delete(id: id, context: childContext, db: db)
        }
    }

    private static func goalCore(_ store: TaisaStore) -> RepositoryCore<GoalRecord> { .init(store: store, spec: .init(table: "goals", entity: "goal", fields: [("id", "id"), ("title", "title"), ("detail", "detail"), ("status", "status"), ("createdAtMS", "created_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["createdAtMS"], appendOnly: false)) }
    private static func milestoneCore(_ store: TaisaStore) -> RepositoryCore<MilestoneRecord> { .init(store: store, spec: .init(table: "milestones", entity: "milestone", fields: [("id", "id"), ("goalID", "goal_id"), ("title", "title"), ("status", "status"), ("targetAtMS", "target_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["goalID"], appendOnly: false)) }
    private static func actionCore(_ store: TaisaStore) -> RepositoryCore<ActionRecord> { .init(store: store, spec: .init(table: "actions", entity: "action", fields: [("id", "id"), ("goalID", "goal_id"), ("milestoneID", "milestone_id"), ("title", "title"), ("detail", "detail"), ("status", "status"), ("dueDay", "due_day"), ("dueAtMS", "due_at_ms"), ("origin", "origin"), ("createdAtMS", "created_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["createdAtMS", "origin"], appendOnly: false)) }
    private static func evidenceCore(_ store: TaisaStore) -> RepositoryCore<EvidenceRecord> { .init(store: store, spec: .init(table: "evidence", entity: "evidence", fields: [("id", "id"), ("goalID", "goal_id"), ("actionID", "action_id"), ("title", "title"), ("detail", "detail"), ("occurredAtMS", "occurred_at_ms"), ("createdAtMS", "created_at_ms")], immutable: ["createdAtMS"], appendOnly: false)) }

    private static func copyAction(_ action: ActionRecord, status: ActionStatus, timestamp: Int64) -> ActionRecord {
        ActionRecord(
            id: action.id,
            goalID: action.goalID,
            title: action.title,
            detail: action.detail,
            status: status.rawValue,
            dueAtMS: action.dueAtMS,
            createdAtMS: action.createdAtMS,
            updatedAtMS: timestamp,
            milestoneID: action.milestoneID,
            dueDay: action.dueDay,
            origin: action.origin
        )
    }

    private static func insertActionEvent(
        actionID: String,
        kind: ActionEventKind,
        from: ActionStatus?,
        to: ActionStatus?,
        detail: String? = nil,
        source: CareerWorkMutationSource,
        sourceID: String?,
        context: MutationContext,
        db: Database
    ) throws -> ActionEventRecord {
        let event = ActionEventRecord(
            id: UUID().uuidString,
            actionID: actionID,
            kind: kind,
            fromStatus: from,
            toStatus: to,
            detail: detail,
            source: source,
            sourceID: sourceID,
            occurredAtMS: context.timestamp
        )
        try db.execute(
            sql: "INSERT INTO action_events (id, action_id, kind, from_status, to_status, detail, source_type, source_id, occurred_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            arguments: [event.id, event.actionID, event.kind.rawValue, event.fromStatus?.rawValue, event.toStatus?.rawValue, event.detail, event.source.rawValue, event.sourceID, event.occurredAtMS]
        )
        return event
    }

    private static func existingCompletion(actionID: String, sourceID: String, db: Database) throws -> ActionCompletionResult? {
        guard let row = try Row.fetchOne(db, sql: """
            SELECT e.id AS event_id, e.occurred_at_ms AS event_occurred_at_ms, v.*
            FROM action_events e
            JOIN action_evidence_links l ON l.completion_event_id = e.id
            JOIN evidence v ON v.id = l.evidence_id
            WHERE e.action_id = ? COLLATE NOCASE AND e.kind = 'completed' AND e.source_id = ? COLLATE NOCASE
            LIMIT 1
            """, arguments: [actionID, sourceID]),
              let action = try fetchAction(id: actionID, db: db) else { return nil }
        let evidence = EvidenceRecord(id: row["id"], goalID: row["goal_id"], actionID: row["action_id"], title: row["title"], detail: row["detail"], occurredAtMS: row["occurred_at_ms"], createdAtMS: row["created_at_ms"])
        let event = ActionEventRecord(id: row["event_id"], actionID: actionID, kind: .completed, fromStatus: .active, toStatus: .completed, detail: nil, source: .user, sourceID: sourceID, occurredAtMS: row["event_occurred_at_ms"])
        return ActionCompletionResult(action: action, evidence: evidence, event: event)
    }
}
