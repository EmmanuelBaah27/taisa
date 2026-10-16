import Foundation
import TaisaContracts
import TaisaStorage

public enum AssistantProposalRoutingError: Error, Equatable, Sendable {
    case malformedPayload
    case staleTarget
    case alreadyResolved
    case unsupported
}

public struct AssistantProposalRouter: Sendable {
    private let proposals: AssistantResponseRepository
    private let goals: GoalRepository
    private let actions: ActionRepository
    private let evidence: EvidenceRepository
    private let weeklyWork: WeeklyWorkRepository
    private let memory: MemoryRepository
    private let insights: InsightRepository

    public init(store: TaisaStore) {
        proposals = AssistantResponseRepository(store: store)
        goals = GoalRepository(store: store)
        actions = ActionRepository(store: store)
        evidence = EvidenceRepository(store: store)
        weeklyWork = WeeklyWorkRepository(store: store)
        memory = MemoryRepository(store: store)
        insights = InsightRepository(store: store)
    }

    public func accept(
        proposalID: String, deviceID: UUID, resolvedAtMS: Int64
    ) async throws -> AssistantProposalRecord {
        guard let stored = try await proposals.proposal(id: proposalID) else {
            throw RepositoryError.notFound
        }
        if stored.state == .accepted || stored.state == .stale || stored.state == .unsupported {
            return stored
        }
        guard stored.state == .pending else { throw AssistantProposalRoutingError.alreadyResolved }
        let decoded: CoachingProposal
        do { decoded = try JSONDecoder().decode(CoachingProposal.self, from: stored.canonicalPayload) }
        catch { return try await mark(stored, state: .unsupported, at: resolvedAtMS) }
        guard kind(decoded) == stored.kind else {
            return try await mark(stored, state: .unsupported, at: resolvedAtMS)
        }

        let target: Target
        do {
            target = try await apply(
                decoded, proposalID: stored.id, deviceID: deviceID,
                timestamp: stored.createdAtMS
            )
        } catch AssistantProposalRoutingError.staleTarget {
            return try await mark(stored, state: .stale, at: resolvedAtMS)
        } catch AssistantProposalRoutingError.unsupported {
            return try await mark(stored, state: .unsupported, at: resolvedAtMS)
        } catch AssistantProposalRoutingError.malformedPayload {
            return try await mark(stored, state: .unsupported, at: resolvedAtMS)
        }
        return try await proposals.resolveProposal(
            id: stored.id, payloadDigest: stored.payloadDigest, state: .accepted,
            targetType: target.type, targetID: target.id, targetVersionID: target.versionID,
            decisionReceipt: "accepted:\(stored.id)", resolvedAtMS: resolvedAtMS
        )
    }

    public func dismiss(proposalID: String, resolvedAtMS: Int64) async throws -> AssistantProposalRecord {
        guard let stored = try await proposals.proposal(id: proposalID) else {
            throw RepositoryError.notFound
        }
        if stored.state == .dismissed { return stored }
        guard stored.state == .pending else { throw AssistantProposalRoutingError.alreadyResolved }
        return try await mark(stored, state: .dismissed, at: resolvedAtMS)
    }

    private func mark(
        _ proposal: AssistantProposalRecord, state: AssistantProposalState, at timestamp: Int64
    ) async throws -> AssistantProposalRecord {
        try await proposals.resolveProposal(
            id: proposal.id, payloadDigest: proposal.payloadDigest, state: state,
            targetType: nil, targetID: nil, targetVersionID: nil,
            decisionReceipt: "\(state.rawValue):\(proposal.id)", resolvedAtMS: timestamp
        )
    }

    private struct Target { let type: String; let id: String; let versionID: String }

    private func apply(
        _ proposal: CoachingProposal, proposalID: String, deviceID: UUID, timestamp: Int64
    ) async throws -> Target {
        let targetID = derivedUUID(from: proposalID, salt: 1)
        let versionID = derivedUUID(from: proposalID, salt: 2)
        let context = MutationContext(
            id: versionID, deviceID: deviceID.uuidString.lowercased(), timestamp: timestamp
        )
        switch proposal {
        case .goal(let value):
            try await goals.create(.init(
                id: targetID, title: value.title, detail: value.description ?? "",
                status: "active", createdAtMS: timestamp, updatedAtMS: timestamp
            ), context: context)
            return .init(type: "goal", id: targetID, versionID: versionID)
        case .action(let value):
            if let goalID = value.goalId, try await goals.get(id: goalID) == nil {
                throw AssistantProposalRoutingError.staleTarget
            }
            try await actions.create(.init(
                id: targetID, goalID: value.goalId, title: value.title,
                detail: value.description ?? "", status: "open",
                dueAtMS: try milliseconds(value.dueAt), createdAtMS: timestamp,
                updatedAtMS: timestamp
            ), context: context)
            return .init(type: "action", id: targetID, versionID: versionID)
        case .weeklyWork(let value):
            guard try await actions.get(id: value.actionId) != nil else {
                throw AssistantProposalRoutingError.staleTarget
            }
            try await weeklyWork.place(
                actionID: value.actionId, weekContaining: try date(value.weekStart),
                plannedDay: try value.plannedDay.map(date), timeZone: TimeZone(secondsFromGMT: 0)!,
                context: context
            )
            return .init(type: "weekly_work", id: value.actionId, versionID: versionID)
        case .evidence(let value):
            guard value.goalId != nil || value.actionId != nil else {
                throw AssistantProposalRoutingError.unsupported
            }
            if let goalID = value.goalId, try await goals.get(id: goalID) == nil {
                throw AssistantProposalRoutingError.staleTarget
            }
            if let actionID = value.actionId, try await actions.get(id: actionID) == nil {
                throw AssistantProposalRoutingError.staleTarget
            }
            try await evidence.create(.init(
                id: targetID, goalID: value.goalId, actionID: value.actionId,
                title: value.statement, detail: value.statement,
                occurredAtMS: try milliseconds(value.occurredAt)!, createdAtMS: timestamp
            ), context: context)
            return .init(type: "evidence", id: targetID, versionID: versionID)
        case .memory(let delta):
            return try await applyMemory(
                delta, targetID: targetID, versionID: versionID, context: context
            )
        case .insight(let value):
            try await insights.create(.init(
                id: targetID, body: value.body, status: .reviewNeeded,
                isTimeSensitive: value.isTimeSensitive,
                homeEligibleUntilMS: try milliseconds(value.homeEligibleUntil),
                createdAtMS: timestamp, updatedAtMS: timestamp
            ), context: context)
            return .init(type: "insight", id: targetID, versionID: versionID)
        }
    }

    private func applyMemory(
        _ delta: MemoryDelta, targetID: String, versionID: String, context: MutationContext
    ) async throws -> Target {
        switch delta {
        case .propose(let candidate, _, _):
            try await memory.create(.init(
                id: targetID, kind: candidate.type.rawValue, content: candidate.statement,
                status: storageStatus(candidate.lifecycle), createdAtMS: context.timestamp,
                updatedAtMS: context.timestamp
            ), context: context)
            return .init(type: "memory", id: targetID, versionID: versionID)
        case .transition(let id, let lifecycle, _, _):
            guard let current = try await memory.get(id: id) else {
                throw AssistantProposalRoutingError.staleTarget
            }
            try await memory.update(.init(
                id: current.id, kind: current.kind, content: current.content,
                status: storageStatus(lifecycle), createdAtMS: current.createdAtMS,
                updatedAtMS: context.timestamp
            ), context: context)
            return .init(type: "memory", id: current.id, versionID: versionID)
        case .support(let id, let sourceMessageID, _):
            guard try await memory.get(id: id) != nil else {
                throw AssistantProposalRoutingError.staleTarget
            }
            let sourceID = derivedUUID(from: targetID, salt: 3)
            try await memory.createSource(.init(
                id: sourceID, memoryItemID: id, sourceType: "message",
                sourceID: sourceMessageID, createdAtMS: context.timestamp
            ), context: context)
            return .init(type: "memory_source", id: sourceID, versionID: versionID)
        }
    }

    private func storageStatus(_ lifecycle: MemoryLifecycle) -> String {
        switch lifecycle {
        case .superseded, .rejected, .archived: "suppressed"
        case .proposed, .active, .paused, .completed: "active"
        }
    }

    private func kind(_ proposal: CoachingProposal) -> String {
        switch proposal {
        case .goal: "goal"; case .action: "action"; case .weeklyWork: "weekly_work"
        case .evidence: "evidence"; case .memory: "memory"; case .insight: "insight"
        }
    }

    private func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let result = formatter.date(from: value) else {
            throw AssistantProposalRoutingError.malformedPayload
        }
        return result
    }

    private func milliseconds(_ value: String?) throws -> Int64? {
        guard let value else { return nil }
        return Int64(try date(value).timeIntervalSince1970 * 1_000)
    }

    private func derivedUUID(from source: String, salt: UInt8) -> String {
        guard var uuid = UUID(uuidString: source)?.uuid else {
            return UUID().uuidString.lowercased()
        }
        uuid.15 ^= salt
        return UUID(uuid: uuid).uuidString.lowercased()
    }
}
