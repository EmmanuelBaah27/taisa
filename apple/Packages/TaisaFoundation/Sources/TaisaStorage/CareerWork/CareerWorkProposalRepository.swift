import CryptoKit
import Foundation
import GRDB

public enum CareerWorkProposalError: Error, Equatable, Sendable {
    case payloadMismatch
    case staleTarget
    case alreadyResolved
    case unsupportedPayload
}

public enum CareerWorkProposalTarget: String, Sendable, Equatable {
    case goal, milestone, action, evidence
}

public struct CareerWorkProposalBasis: Sendable, Equatable {
    public let entity: CareerWorkProposalTarget
    public let id: String
    public let versionID: String

    public init(entity: CareerWorkProposalTarget, id: String, versionID: String) {
        self.entity = entity
        self.id = id
        self.versionID = versionID
    }
}

public enum CareerWorkProposalPayload: Sendable, Equatable {
    case goal(title: String, detail: String)
    case milestone(goalID: String, title: String, targetAtMS: Int64?)
    case action(goalID: String?, title: String, detail: String, dueAtMS: Int64?)
    case evidence(goalID: String?, actionID: String?, title: String, detail: String, occurredAtMS: Int64, origin: EvidenceOrigin, originID: String?)

    public var target: CareerWorkProposalTarget {
        switch self {
        case .goal: .goal
        case .milestone: .milestone
        case .action: .action
        case .evidence: .evidence
        }
    }

    public var digest: String {
        let bytes = (try? JSONSerialization.data(withJSONObject: canonicalObject, options: [.sortedKeys])) ?? Data()
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private var canonicalObject: [String: Any] {
        switch self {
        case let .goal(title, detail):
            ["kind": "goal", "title": title, "detail": detail]
        case let .milestone(goalID, title, targetAtMS):
            ["kind": "milestone", "goalID": goalID, "title": title, "targetAtMS": targetAtMS ?? NSNull()]
        case let .action(goalID, title, detail, dueAtMS):
            ["kind": "action", "goalID": goalID ?? NSNull(), "title": title, "detail": detail, "dueAtMS": dueAtMS ?? NSNull()]
        case let .evidence(goalID, actionID, title, detail, occurredAtMS, origin, originID):
            ["kind": "evidence", "goalID": goalID ?? NSNull(), "actionID": actionID ?? NSNull(), "title": title, "detail": detail, "occurredAtMS": occurredAtMS, "origin": origin.rawValue, "originID": originID ?? NSNull()]
        }
    }
}

public struct CareerWorkProposal: Sendable, Equatable {
    public let id: String
    public let targetID: String
    public let targetVersionID: String
    public let basis: CareerWorkProposalBasis?
    public let payload: CareerWorkProposalPayload
    public let payloadDigest: String

    public init(id: String, targetID: String, targetVersionID: String, basis: CareerWorkProposalBasis?, payload: CareerWorkProposalPayload, payloadDigest: String) {
        self.id = id
        self.targetID = targetID
        self.targetVersionID = targetVersionID
        self.basis = basis
        self.payload = payload
        self.payloadDigest = payloadDigest
    }

    public var computedPayloadDigest: String { payload.digest }
}

public struct CareerWorkProposalResolution: Sendable, Equatable {
    public let proposalID: String
    public let target: CareerWorkProposalTarget
    public let targetID: String
    public let targetVersionID: String
    public let payloadDigest: String
    public let decision: ProposalDecision
}

public struct CareerWorkProposalRepository: Sendable {
    private let store: TaisaStore

    public init(store: TaisaStore) { self.store = store }

    public func accept(_ proposal: CareerWorkProposal, context: MutationContext) async throws -> CareerWorkProposalResolution {
        try await resolve(proposal, payload: proposal.payload, digest: proposal.payloadDigest, decision: .accepted, context: context)
    }

    public func correct(_ proposal: CareerWorkProposal, with payload: CareerWorkProposalPayload, payloadDigest: String, context: MutationContext) async throws -> CareerWorkProposalResolution {
        guard proposal.computedPayloadDigest == proposal.payloadDigest else { throw CareerWorkProposalError.payloadMismatch }
        return try await resolve(proposal, payload: payload, digest: payloadDigest, decision: .corrected, context: context)
    }

    public func reject(_ proposal: CareerWorkProposal, context: MutationContext) async throws -> CareerWorkProposalResolution {
        guard proposal.computedPayloadDigest == proposal.payloadDigest else { throw CareerWorkProposalError.payloadMismatch }
        return try await store.write { db in
            if let existing = try Self.receipt(proposalID: proposal.id, db: db) {
                return try Self.replay(existing, proposal: proposal, digest: proposal.payloadDigest, decision: .rejected)
            }
            let result = Self.resolution(proposal, digest: proposal.payloadDigest, decision: .rejected)
            try Self.insertReceipt(result, resolvedAtMS: context.timestamp, db: db)
            return result
        }
    }

    public func undo(proposalID: String, payloadDigest: String, context: MutationContext) async throws -> CareerWorkProposalResolution {
        try await store.write { db in
            guard let receipt = try Self.receipt(proposalID: proposalID, db: db), receipt.payloadDigest == payloadDigest else {
                throw CareerWorkProposalError.payloadMismatch
            }
            if receipt.decision == .undone { return receipt.resolution }
            guard receipt.decision == .accepted || receipt.decision == .corrected else { throw CareerWorkProposalError.alreadyResolved }
            guard try Self.currentVersion(entity: receipt.target, id: receipt.targetID, db: db) == receipt.targetVersionID else {
                throw CareerWorkProposalError.staleTarget
            }
            try Self.delete(target: receipt.target, id: receipt.targetID, context: context, store: store, db: db)
            try db.execute(sql: "UPDATE career_work_proposal_receipts SET decision = 'undone', resolved_at_ms = ? WHERE proposal_id = ?", arguments: [context.timestamp, proposalID])
            return .init(proposalID: receipt.proposalID, target: receipt.target, targetID: receipt.targetID, targetVersionID: receipt.targetVersionID, payloadDigest: receipt.payloadDigest, decision: .undone)
        }
    }

    private func resolve(_ proposal: CareerWorkProposal, payload: CareerWorkProposalPayload, digest: String, decision: ProposalDecision, context: MutationContext) async throws -> CareerWorkProposalResolution {
        guard proposal.computedPayloadDigest == proposal.payloadDigest, payload.digest == digest else { throw CareerWorkProposalError.payloadMismatch }
        guard proposal.payload.target == payload.target else { throw CareerWorkProposalError.unsupportedPayload }
        return try await store.write { db in
            if let existing = try Self.receipt(proposalID: proposal.id, db: db) {
                return try Self.replay(existing, proposal: proposal, digest: digest, decision: decision)
            }
            if let basis = proposal.basis,
               try Self.currentVersion(entity: basis.entity, id: basis.id, db: db) != basis.versionID {
                throw CareerWorkProposalError.staleTarget
            }
            let mutation = MutationContext(id: proposal.targetVersionID, deviceID: context.deviceID, timestamp: context.timestamp)
            try Self.apply(payload, targetID: proposal.targetID, proposalID: proposal.id, context: mutation, store: store, db: db)
            let result = Self.resolution(proposal, digest: digest, decision: decision)
            try Self.insertReceipt(result, resolvedAtMS: context.timestamp, db: db)
            return result
        }
    }

    private static func apply(_ payload: CareerWorkProposalPayload, targetID: String, proposalID: String, context: MutationContext, store: TaisaStore, db: Database) throws {
        switch payload {
        case let .goal(title, detail):
            let title = try CareerWorkTitle.validating(title).value
            let record = GoalRecord(id: targetID, title: title, detail: detail, status: GoalStatus.active.rawValue, createdAtMS: context.timestamp, updatedAtMS: context.timestamp)
            try core(store, table: "goals", entity: "goal", fields: [("id", "id"), ("title", "title"), ("detail", "detail"), ("status", "status"), ("createdAtMS", "created_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["createdAtMS"], as: GoalRecord.self).create(record, context: context, db: db)
            try insertEvent(entity: "goal", id: targetID, status: record.status, proposalID: proposalID, context: context, db: db)
        case let .milestone(goalID, title, targetAtMS):
            let record = MilestoneRecord(id: targetID, goalID: goalID, title: try CareerWorkTitle.validating(title).value, status: "open", targetAtMS: targetAtMS, updatedAtMS: context.timestamp)
            try core(store, table: "milestones", entity: "milestone", fields: [("id", "id"), ("goalID", "goal_id"), ("title", "title"), ("status", "status"), ("targetAtMS", "target_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["goalID"], as: MilestoneRecord.self).create(record, context: context, db: db)
            try insertEvent(entity: "milestone", id: targetID, status: record.status, proposalID: proposalID, context: context, db: db)
        case let .action(goalID, title, detail, dueAtMS):
            let record = ActionRecord(id: targetID, goalID: goalID, title: try CareerWorkTitle.validating(title).value, detail: detail, status: ActionStatus.open.rawValue, dueAtMS: dueAtMS, createdAtMS: context.timestamp, updatedAtMS: context.timestamp)
            try core(store, table: "actions", entity: "action", fields: [("id", "id"), ("goalID", "goal_id"), ("title", "title"), ("detail", "detail"), ("status", "status"), ("dueAtMS", "due_at_ms"), ("createdAtMS", "created_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["createdAtMS"], as: ActionRecord.self).create(record, context: context, db: db)
            try insertEvent(entity: "action", id: targetID, status: record.status, proposalID: proposalID, context: context, db: db)
        case let .evidence(goalID, actionID, title, detail, occurredAtMS, origin, originID):
            guard goalID != nil || actionID != nil else { throw CareerWorkContractError.invalidRelationship }
            let record = EvidenceRecord(id: targetID, goalID: goalID, actionID: actionID, title: try CareerWorkTitle.validating(title).value, detail: detail, occurredAtMS: occurredAtMS, createdAtMS: context.timestamp)
            try core(store, table: "evidence", entity: "evidence", fields: [("id", "id"), ("goalID", "goal_id"), ("actionID", "action_id"), ("title", "title"), ("detail", "detail"), ("occurredAtMS", "occurred_at_ms"), ("createdAtMS", "created_at_ms")], immutable: ["createdAtMS"], as: EvidenceRecord.self).create(record, context: context, db: db)
            try db.execute(sql: "INSERT INTO evidence_provenance (evidence_id, origin_type, origin_id, created_at_ms) VALUES (?, ?, ?, ?)", arguments: [targetID, origin.rawValue, originID, context.timestamp])
        }
    }

    private static func core<Record: DomainRecord>(_ store: TaisaStore, table: String, entity: String, fields: [(String, String)], immutable: Set<String>, as: Record.Type) -> RepositoryCore<Record> {
        .init(store: store, spec: .init(table: table, entity: entity, fields: fields, immutable: immutable, appendOnly: false))
    }

    private static func insertEvent(entity: String, id: String, status: String, proposalID: String, context: MutationContext, db: Database) throws {
        try db.execute(sql: "INSERT INTO career_work_events (id, entity_type, entity_id, transition, from_status, to_status, source_type, source_id, occurred_at_ms) VALUES (?, ?, ?, 'created', NULL, ?, 'proposal', ?, ?)", arguments: [UUID().uuidString, entity, id, status, proposalID, context.timestamp])
    }

    private static func currentVersion(entity: CareerWorkProposalTarget, id: String, db: Database) throws -> String? {
        try String.fetchOne(db, sql: "SELECT version_id FROM field_versions WHERE entity_type = ? AND entity_id = ? COLLATE NOCASE AND field_name = '__record' ORDER BY rowid DESC LIMIT 1", arguments: [entity.rawValue, id])
    }

    private static func delete(target: CareerWorkProposalTarget, id: String, context: MutationContext, store: TaisaStore, db: Database) throws {
        switch target {
        case .goal:
            try core(store, table: "goals", entity: "goal", fields: [("id", "id"), ("title", "title"), ("detail", "detail"), ("status", "status"), ("createdAtMS", "created_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["createdAtMS"], as: GoalRecord.self).delete(id: id, context: context, db: db)
        case .milestone:
            try core(store, table: "milestones", entity: "milestone", fields: [("id", "id"), ("goalID", "goal_id"), ("title", "title"), ("status", "status"), ("targetAtMS", "target_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["goalID"], as: MilestoneRecord.self).delete(id: id, context: context, db: db)
        case .action:
            try core(store, table: "actions", entity: "action", fields: [("id", "id"), ("goalID", "goal_id"), ("title", "title"), ("detail", "detail"), ("status", "status"), ("dueAtMS", "due_at_ms"), ("createdAtMS", "created_at_ms"), ("updatedAtMS", "updated_at_ms")], immutable: ["createdAtMS"], as: ActionRecord.self).delete(id: id, context: context, db: db)
        case .evidence:
            try core(store, table: "evidence", entity: "evidence", fields: [("id", "id"), ("goalID", "goal_id"), ("actionID", "action_id"), ("title", "title"), ("detail", "detail"), ("occurredAtMS", "occurred_at_ms"), ("createdAtMS", "created_at_ms")], immutable: ["createdAtMS"], as: EvidenceRecord.self).delete(id: id, context: context, db: db)
        }
    }

    private struct Receipt {
        let proposalID: String
        let target: CareerWorkProposalTarget
        let targetID: String
        let targetVersionID: String
        let payloadDigest: String
        let decision: ProposalDecision
        var resolution: CareerWorkProposalResolution { .init(proposalID: proposalID, target: target, targetID: targetID, targetVersionID: targetVersionID, payloadDigest: payloadDigest, decision: decision) }
    }

    private static func receipt(proposalID: String, db: Database) throws -> Receipt? {
        try Row.fetchOne(db, sql: "SELECT * FROM career_work_proposal_receipts WHERE proposal_id = ? COLLATE NOCASE", arguments: [proposalID]).flatMap { row in
            guard let target = CareerWorkProposalTarget(rawValue: row["target_type"]), let decision = ProposalDecision(rawValue: row["decision"]) else { return nil }
            return Receipt(proposalID: row["proposal_id"], target: target, targetID: row["target_id"], targetVersionID: row["target_version_id"], payloadDigest: row["payload_digest"], decision: decision)
        }
    }

    private static func resolution(_ proposal: CareerWorkProposal, digest: String, decision: ProposalDecision) -> CareerWorkProposalResolution {
        .init(proposalID: proposal.id, target: proposal.payload.target, targetID: proposal.targetID, targetVersionID: proposal.targetVersionID, payloadDigest: digest, decision: decision)
    }

    private static func insertReceipt(_ value: CareerWorkProposalResolution, resolvedAtMS: Int64, db: Database) throws {
        try db.execute(sql: "INSERT INTO career_work_proposal_receipts (id, proposal_id, target_type, target_id, target_version_id, payload_digest, decision, resolved_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", arguments: [UUID().uuidString, value.proposalID, value.target.rawValue, value.targetID, value.targetVersionID, value.payloadDigest, value.decision.rawValue, resolvedAtMS])
    }

    private static func replay(_ receipt: Receipt, proposal: CareerWorkProposal, digest: String, decision: ProposalDecision) throws -> CareerWorkProposalResolution {
        guard receipt.target == proposal.payload.target,
              receipt.targetID == proposal.targetID,
              receipt.targetVersionID == proposal.targetVersionID,
              receipt.payloadDigest == digest,
              receipt.decision == decision else { throw CareerWorkProposalError.alreadyResolved }
        return receipt.resolution
    }
}
