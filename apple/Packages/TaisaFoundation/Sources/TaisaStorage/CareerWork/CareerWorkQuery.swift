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

    private static func goal(_ row: Row) -> GoalRecord { .init(id: row["id"], title: row["title"], detail: row["detail"], status: row["status"], createdAtMS: row["created_at_ms"], updatedAtMS: row["updated_at_ms"]) }
    private static func milestone(_ row: Row) -> MilestoneRecord { .init(id: row["id"], goalID: row["goal_id"], title: row["title"], status: row["status"], targetAtMS: row["target_at_ms"], updatedAtMS: row["updated_at_ms"]) }
    private static func action(_ row: Row) -> ActionRecord { .init(id: row["id"], goalID: row["goal_id"], title: row["title"], detail: row["detail"], status: row["status"], dueAtMS: row["due_at_ms"], createdAtMS: row["created_at_ms"], updatedAtMS: row["updated_at_ms"]) }
    private static func evidence(_ row: Row) -> EvidenceRecord { .init(id: row["id"], goalID: row["goal_id"], actionID: row["action_id"], title: row["title"], detail: row["detail"], occurredAtMS: row["occurred_at_ms"], createdAtMS: row["created_at_ms"]) }
}
