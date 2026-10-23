import GRDB

public struct CareerWorkProgress: Sendable, Equatable {
    public let summary: String
    public let completedMilestones: Int
    public let milestoneCount: Int
    public let completedActions: Int
    public let actionCount: Int
    public let evidenceCount: Int

    public init(summary: String, completedMilestones: Int, milestoneCount: Int, completedActions: Int, actionCount: Int, evidenceCount: Int) {
        self.summary = summary
        self.completedMilestones = completedMilestones
        self.milestoneCount = milestoneCount
        self.completedActions = completedActions
        self.actionCount = actionCount
        self.evidenceCount = evidenceCount
    }
}

public struct EvidenceProvenance: Sendable, Equatable {
    public let evidenceID: String
    public let origin: EvidenceOrigin
    public let originID: String?
    public let supersedesEvidenceID: String?

    public init(evidenceID: String, origin: EvidenceOrigin, originID: String?, supersedesEvidenceID: String?) {
        self.evidenceID = evidenceID
        self.origin = origin
        self.originID = originID
        self.supersedesEvidenceID = supersedesEvidenceID
    }
}

public struct CareerGoalSnapshot: Sendable, Equatable {
    public let goal: GoalRecord
    public let milestones: [MilestoneRecord]
    public let actions: [ActionRecord]
    public let evidence: [EvidenceRecord]
    public let provenance: [EvidenceProvenance]
    public let progress: CareerWorkProgress

    public init(goal: GoalRecord, milestones: [MilestoneRecord], actions: [ActionRecord], evidence: [EvidenceRecord], provenance: [EvidenceProvenance], progress: CareerWorkProgress) {
        self.goal = goal
        self.milestones = milestones
        self.actions = actions
        self.evidence = evidence
        self.provenance = provenance
        self.progress = progress
    }
}

public struct CareerWorkOverview: Sendable, Equatable {
    public let active: [GoalRecord]
    public let paused: [GoalRecord]
    public let completed: [GoalRecord]
    public let archived: [GoalRecord]

    public init(active: [GoalRecord], paused: [GoalRecord], completed: [GoalRecord], archived: [GoalRecord]) {
        self.active = active
        self.paused = paused
        self.completed = completed
        self.archived = archived
    }
}

public struct ActionCollectionFilter: Sendable, Equatable {
    public let lifecycle: ActionLifecycleFilter
    public let goalID: String?
    public let milestoneID: String?
    public let due: ActionDueFilter
    public let weekStartMS: Int64?
    public let origin: ActionOrigin?

    public init(lifecycle: ActionLifecycleFilter, goalID: String? = nil, milestoneID: String? = nil, due: ActionDueFilter = .all, weekStartMS: Int64? = nil, origin: ActionOrigin? = nil) {
        self.lifecycle = lifecycle; self.goalID = goalID; self.milestoneID = milestoneID
        self.due = due; self.weekStartMS = weekStartMS; self.origin = origin
    }
}

public struct ActionDetailSnapshot: Sendable, Equatable {
    public let action: ActionRecord
    public let goal: GoalRecord?
    public let milestone: MilestoneRecord?
    public let checklist: [ActionChecklistItemRecord]
    public let events: [ActionEventRecord]
    public let currentEvidence: [EvidenceRecord]
    public let supersededEvidence: [EvidenceRecord]
    public let placement: WeeklyPlacementRecord?
}

public struct ActionDuplicateReview: Sendable, Equatable {
    public let candidates: [ActionRecord]
    public let decisions: [ActionDuplicateDecision]
    public init(candidates: [ActionRecord], decisions: [ActionDuplicateDecision] = ActionDuplicateDecision.allCases) {
        self.candidates = candidates; self.decisions = decisions
    }
}

public struct CareerWorkQuery: Sendable {
    private let store: TaisaStore
    public init(store: TaisaStore) { self.store = store }

    public func overview() async throws -> CareerWorkOverview {
        try await store.read { db in
            let goals = try Row.fetchAll(db, sql: "SELECT g.*, EXISTS (SELECT 1 FROM career_work_archives a WHERE a.entity_type = 'goal' AND a.entity_id = g.id AND a.restored_at_ms IS NULL) AS archived FROM goals g WHERE NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'goal' AND t.entity_id = g.id) ORDER BY g.updated_at_ms DESC, g.id ASC")
            var active: [GoalRecord] = [], paused: [GoalRecord] = [], completed: [GoalRecord] = [], archived: [GoalRecord] = []
            for row in goals {
                let goal = Self.goal(row)
                if (row["archived"] as Int) == 1 { archived.append(goal) }
                else if goal.status == GoalStatus.paused.rawValue { paused.append(goal) }
                else if goal.status == GoalStatus.completed.rawValue { completed.append(goal) }
                else { active.append(goal) }
            }
            return CareerWorkOverview(active: active, paused: paused, completed: completed, archived: archived)
        }
    }

    public func goal(id: String) async throws -> CareerGoalSnapshot? {
        try await store.read { db in
            guard let goalRow = try Row.fetchOne(db, sql: "SELECT * FROM goals WHERE id = ? COLLATE NOCASE AND NOT EXISTS (SELECT 1 FROM tombstones WHERE entity_type = 'goal' AND entity_id = ? COLLATE NOCASE)", arguments: [id, id]) else { return nil }
            let goal = Self.goal(goalRow)
            let milestones = try Row.fetchAll(db, sql: "SELECT * FROM milestones WHERE goal_id = ? COLLATE NOCASE AND NOT EXISTS (SELECT 1 FROM tombstones WHERE entity_type = 'milestone' AND entity_id = milestones.id) ORDER BY updated_at_ms, id", arguments: [id]).map(Self.milestone)
            let actions = try Row.fetchAll(db, sql: "SELECT * FROM actions WHERE goal_id = ? COLLATE NOCASE AND NOT EXISTS (SELECT 1 FROM tombstones WHERE entity_type = 'action' AND entity_id = actions.id) ORDER BY updated_at_ms, id", arguments: [id]).map(Self.action)
            let evidence = try Row.fetchAll(db, sql: "SELECT DISTINCT e.* FROM evidence e LEFT JOIN actions a ON a.id = e.action_id WHERE (e.goal_id = ? COLLATE NOCASE OR a.goal_id = ? COLLATE NOCASE) AND NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'evidence' AND t.entity_id = e.id) ORDER BY e.occurred_at_ms, e.id", arguments: [id, id]).map(Self.evidence)
            let provenance = try Row.fetchAll(db, sql: "SELECT p.* FROM evidence_provenance p JOIN evidence e ON e.id = p.evidence_id LEFT JOIN actions a ON a.id = e.action_id WHERE e.goal_id = ? COLLATE NOCASE OR a.goal_id = ? COLLATE NOCASE ORDER BY p.created_at_ms, p.evidence_id", arguments: [id, id]).compactMap { row -> EvidenceProvenance? in
                guard let origin = EvidenceOrigin(rawValue: row["origin_type"]) else { return nil }
                return EvidenceProvenance(evidenceID: row["evidence_id"], origin: origin, originID: row["origin_id"], supersedesEvidenceID: row["supersedes_evidence_id"])
            }
            let completedMilestones = milestones.filter { $0.status == "completed" }.count
            let completedActions = actions.filter { $0.status == "completed" }.count
            let noun = evidence.count == 1 ? "item" : "items"
            let summary = "\(completedMilestones) of \(milestones.count) milestones and \(completedActions) of \(actions.count) actions completed; \(evidence.count) evidence \(noun) recorded."
            return CareerGoalSnapshot(goal: goal, milestones: milestones, actions: actions, evidence: evidence, provenance: provenance, progress: .init(summary: summary, completedMilestones: completedMilestones, milestoneCount: milestones.count, completedActions: completedActions, actionCount: actions.count, evidenceCount: evidence.count))
        }
    }

    public func action(id: String) async throws -> ActionRecord? {
        try await store.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM actions WHERE id = ? COLLATE NOCASE AND NOT EXISTS (SELECT 1 FROM tombstones WHERE entity_type = 'action' AND entity_id = ? COLLATE NOCASE)", arguments: [id, id]).map(Self.action)
        }
    }

    public func actions(filter: ActionCollectionFilter, localDay: ActionDueDay) async throws -> [ActionRecord] {
        try await store.read { db in
            var clauses = ["a.status = ?", "NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'action' AND t.entity_id = a.id COLLATE NOCASE)"]
            var arguments: [DatabaseValueConvertible?] = [filter.lifecycle.rawValue]
            if let goalID = filter.goalID { clauses.append("a.goal_id = ? COLLATE NOCASE"); arguments.append(goalID) }
            if let milestoneID = filter.milestoneID { clauses.append("a.milestone_id = ? COLLATE NOCASE"); arguments.append(milestoneID) }
            switch filter.due {
            case .all: break
            case .overdue: clauses.append("a.due_day < ?"); arguments.append(localDay.rawValue)
            case .due: clauses.append("a.due_day = ?"); arguments.append(localDay.rawValue)
            case .noDueDay: clauses.append("a.due_day IS NULL")
            }
            if let weekStartMS = filter.weekStartMS {
                clauses.append("EXISTS (SELECT 1 FROM weekly_placements p WHERE p.action_id = a.id COLLATE NOCASE AND p.week_start_ms = ? AND NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'weekly_placement' AND t.entity_id = p.id COLLATE NOCASE))")
                arguments.append(weekStartMS)
            }
            if let origin = filter.origin { clauses.append("a.origin = ?"); arguments.append(origin.rawValue) }
            let sql = "SELECT a.* FROM actions a WHERE \(clauses.joined(separator: " AND ")) ORDER BY a.due_day IS NULL, a.due_day, a.updated_at_ms DESC, a.id ASC"
            return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments)).map(Self.action)
        }
    }

    public func actionDetail(id: String) async throws -> ActionDetailSnapshot? {
        try await store.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM actions a WHERE a.id = ? COLLATE NOCASE AND NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'action' AND t.entity_id = a.id COLLATE NOCASE)", arguments: [id]) else { return nil }
            let action = Self.action(row)
            let goal = try action.goalID.flatMap { goalID in try Row.fetchOne(db, sql: "SELECT * FROM goals WHERE id = ? COLLATE NOCASE", arguments: [goalID]).map(Self.goal) }
            let milestone = try action.milestoneID.flatMap { milestoneID in try Row.fetchOne(db, sql: "SELECT * FROM milestones WHERE id = ? COLLATE NOCASE", arguments: [milestoneID]).map(Self.milestone) }
            let checklist = try Row.fetchAll(db, sql: "SELECT * FROM action_checklist_items WHERE action_id = ? COLLATE NOCASE ORDER BY position, id", arguments: [id]).map(Self.checklistItem)
            let events = try Row.fetchAll(db, sql: "SELECT * FROM action_events WHERE action_id = ? COLLATE NOCASE ORDER BY occurred_at_ms, id", arguments: [id]).compactMap(Self.actionEvent)
            let currentEvidence = try Row.fetchAll(db, sql: "SELECT e.* FROM evidence e JOIN action_evidence_links l ON l.evidence_id = e.id WHERE e.action_id = ? COLLATE NOCASE AND l.superseded_by_event_id IS NULL AND NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'evidence' AND t.entity_id = e.id COLLATE NOCASE) ORDER BY e.occurred_at_ms, e.id", arguments: [id]).map(Self.evidence)
            let supersededEvidence = try Row.fetchAll(db, sql: "SELECT e.* FROM evidence e JOIN action_evidence_links l ON l.evidence_id = e.id WHERE e.action_id = ? COLLATE NOCASE AND l.superseded_by_event_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'evidence' AND t.entity_id = e.id COLLATE NOCASE) ORDER BY e.occurred_at_ms, e.id", arguments: [id]).map(Self.evidence)
            let placement = try Row.fetchOne(db, sql: "SELECT p.* FROM weekly_placements p WHERE p.action_id = ? COLLATE NOCASE AND NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'weekly_placement' AND t.entity_id = p.id COLLATE NOCASE) ORDER BY p.updated_at_ms DESC, p.id LIMIT 1", arguments: [id]).map(Self.placement)
            return ActionDetailSnapshot(action: action, goal: goal, milestone: milestone, checklist: checklist, events: events, currentEvidence: currentEvidence, supersededEvidence: supersededEvidence, placement: placement)
        }
    }

    public func duplicateCandidates(title: String, excludingActionID: String?) async throws -> [ActionRecord] {
        let normalized = Self.normalizedTitle(title)
        return try await store.read { db in
            try Row.fetchAll(db, sql: "SELECT a.* FROM actions a WHERE NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'action' AND t.entity_id = a.id COLLATE NOCASE) ORDER BY a.updated_at_ms DESC, a.id").map(Self.action).filter {
                $0.id.caseInsensitiveCompare(excludingActionID ?? "") != .orderedSame && Self.normalizedTitle($0.title) == normalized
            }
        }
    }

    public func duplicateReview(title: String, excludingActionID: String? = nil) async throws -> ActionDuplicateReview {
        ActionDuplicateReview(candidates: try await duplicateCandidates(title: title, excludingActionID: excludingActionID))
    }

    public func evidence(id: String) async throws -> EvidenceRecord? {
        try await store.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM evidence WHERE id = ? COLLATE NOCASE AND NOT EXISTS (SELECT 1 FROM tombstones WHERE entity_type = 'evidence' AND entity_id = ? COLLATE NOCASE)", arguments: [id, id]).map(Self.evidence)
        }
    }

    private static func goal(_ row: Row) -> GoalRecord { .init(id: row["id"], title: row["title"], detail: row["detail"], status: row["status"], createdAtMS: row["created_at_ms"], updatedAtMS: row["updated_at_ms"]) }
    private static func milestone(_ row: Row) -> MilestoneRecord { .init(id: row["id"], goalID: row["goal_id"], title: row["title"], status: row["status"], targetAtMS: row["target_at_ms"], updatedAtMS: row["updated_at_ms"]) }
    private static func action(_ row: Row) -> ActionRecord { .init(id: row["id"], goalID: row["goal_id"], title: row["title"], detail: row["detail"], status: row["status"], dueAtMS: row["due_at_ms"], createdAtMS: row["created_at_ms"], updatedAtMS: row["updated_at_ms"], milestoneID: row["milestone_id"], dueDay: (row["due_day"] as String?).flatMap(ActionDueDay.init(rawValue:)), origin: ActionOrigin(rawValue: row["origin"] as String) ?? .manual) }
    private static func evidence(_ row: Row) -> EvidenceRecord { .init(id: row["id"], goalID: row["goal_id"], actionID: row["action_id"], title: row["title"], detail: row["detail"], occurredAtMS: row["occurred_at_ms"], createdAtMS: row["created_at_ms"]) }
    private static func checklistItem(_ row: Row) -> ActionChecklistItemRecord { .init(id: row["id"], actionID: row["action_id"], title: row["title"], state: ActionChecklistState(rawValue: row["state"])!, position: row["position"], promotedActionID: row["promoted_action_id"], createdAtMS: row["created_at_ms"], updatedAtMS: row["updated_at_ms"]) }
    private static func actionEvent(_ row: Row) -> ActionEventRecord? {
        guard let kind = ActionEventKind(rawValue: row["kind"]), let source = CareerWorkMutationSource(rawValue: row["source_type"]) else { return nil }
        return .init(id: row["id"], actionID: row["action_id"], kind: kind, fromStatus: (row["from_status"] as String?).flatMap(ActionStatus.init(rawValue:)), toStatus: (row["to_status"] as String?).flatMap(ActionStatus.init(rawValue:)), detail: row["detail"], source: source, sourceID: row["source_id"], occurredAtMS: row["occurred_at_ms"])
    }
    private static func placement(_ row: Row) -> WeeklyPlacementRecord { .init(id: row["id"], actionID: row["action_id"], weekStartMS: row["week_start_ms"], plannedDayMS: row["planned_day_ms"], createdAtMS: row["created_at_ms"], updatedAtMS: row["updated_at_ms"]) }
    private static func normalizedTitle(_ title: String) -> String { title.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased() }
}
