import CryptoKit
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
    private let acceptance: AssistantProposalAcceptanceRepository
    private let goals: GoalRepository
    private let actions: ActionRepository
    private let evidence: EvidenceRepository
    private let weeklyWork: WeeklyWorkRepository
    private let memory: MemoryRepository
    private let insights: InsightRepository

    public init(store: TaisaStore) {
        proposals = AssistantResponseRepository(store: store)
        acceptance = AssistantProposalAcceptanceRepository(store: store)
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
        catch { return try await mark(stored, state: .unsupported, deviceID: deviceID, at: resolvedAtMS) }
        guard kind(decoded) == stored.kind else {
            return try await mark(stored, state: .unsupported, deviceID: deviceID, at: resolvedAtMS)
        }

        let prepared: PreparedDestination
        do {
            prepared = try await prepare(
                decoded, proposalID: stored.id, deviceID: deviceID,
                timestamp: stored.createdAtMS
            )
        } catch AssistantProposalRoutingError.staleTarget {
            return try await mark(stored, state: .stale, deviceID: deviceID, at: resolvedAtMS)
        } catch AssistantProposalRoutingError.unsupported {
            return try await mark(stored, state: .unsupported, deviceID: deviceID, at: resolvedAtMS)
        } catch AssistantProposalRoutingError.malformedPayload {
            return try await mark(stored, state: .unsupported, deviceID: deviceID, at: resolvedAtMS)
        }
        do {
            return try await acceptance.accept(
                proposalID: stored.id, payloadDigest: stored.payloadDigest,
                destination: prepared.destination, context: prepared.context,
                targetType: prepared.target.type, targetID: prepared.target.id,
                targetVersionID: prepared.target.versionID,
                decisionReceipt: "accepted:\(stored.id)", resolvedAtMS: resolvedAtMS
            )
        } catch AssistantProposalAcceptanceError.staleTarget {
            return try await mark(stored, state: .stale, deviceID: deviceID, at: resolvedAtMS)
        }
    }

    public func dismiss(proposalID: String, resolvedAtMS: Int64) async throws -> AssistantProposalRecord {
        try await dismiss(proposalID: proposalID, deviceID: UUID(), resolvedAtMS: resolvedAtMS)
    }

    public func dismiss(proposalID: String, deviceID: UUID, resolvedAtMS: Int64) async throws -> AssistantProposalRecord {
        guard let stored = try await proposals.proposal(id: proposalID) else {
            throw RepositoryError.notFound
        }
        if stored.state == .dismissed { return stored }
        guard stored.state == .pending else { throw AssistantProposalRoutingError.alreadyResolved }
        return try await mark(stored, state: .dismissed, deviceID: deviceID, at: resolvedAtMS)
    }

    private func mark(
        _ proposal: AssistantProposalRecord, state: AssistantProposalState, deviceID: UUID, at timestamp: Int64
    ) async throws -> AssistantProposalRecord {
        try await proposals.resolveProposal(
            id: proposal.id, payloadDigest: proposal.payloadDigest, state: state,
            targetType: nil, targetID: nil, targetVersionID: nil,
            decisionReceipt: "\(state.rawValue):\(proposal.id)", resolvedAtMS: timestamp,
            context: .init(id: UUID().uuidString, deviceID: deviceID.uuidString.lowercased(), timestamp: timestamp)
        )
    }

    private struct Target { let type: String; let id: String; let versionID: String }
    private struct PreparedDestination {
        let destination: AssistantProposalDestination
        let context: MutationContext
        let target: Target
    }

    private func prepare(
        _ proposal: CoachingProposal, proposalID: String, deviceID: UUID, timestamp: Int64
    ) async throws -> PreparedDestination {
        let targetID = derivedUUID(from: proposalID, salt: 1)
        let versionID = derivedUUID(from: proposalID, salt: 2)
        let context = MutationContext(
            id: versionID, deviceID: deviceID.uuidString.lowercased(), timestamp: timestamp
        )
        switch proposal {
        case .goal(let value):
            let record = GoalRecord(
                id: targetID, title: value.title, detail: value.description ?? "",
                status: "active", createdAtMS: timestamp, updatedAtMS: timestamp
            )
            return .init(destination: .goal(record), context: context, target: .init(type: "goal", id: targetID, versionID: versionID))
        case .action(let value):
            if let goalID = value.goalId, try await goals.get(id: goalID) == nil {
                throw AssistantProposalRoutingError.staleTarget
            }
            let record = ActionRecord(
                id: targetID, goalID: value.goalId, title: value.title,
                detail: value.description ?? "", status: "open",
                dueAtMS: try milliseconds(value.dueAt), createdAtMS: timestamp,
                updatedAtMS: timestamp
            )
            return .init(destination: .action(record), context: context, target: .init(type: "action", id: targetID, versionID: versionID))
        case .weeklyWork(let value):
            guard try await actions.get(id: value.actionId) != nil else {
                throw AssistantProposalRoutingError.staleTarget
            }
            let dates = try WeekCalendar(timeZone: TimeZone(secondsFromGMT: 0)!).placement(
                weekContaining: try date(value.weekStart), plannedDay: try value.plannedDay.map(date)
            )
            let weekStart = Int64((dates.weekStart.timeIntervalSince1970 * 1_000).rounded())
            let plannedDay = dates.plannedDay.map { Int64(($0.timeIntervalSince1970 * 1_000).rounded()) }
            let placement = WeeklyPlacementRecord(id: targetID, actionID: value.actionId, weekStartMS: weekStart, plannedDayMS: plannedDay, createdAtMS: timestamp, updatedAtMS: timestamp)
            let eventID = derivedUUID(from: proposalID, salt: 3)
            let event = WorkEventRecord(id: eventID, actionID: value.actionId, kind: .placed, fromWeekStartMS: nil, toWeekStartMS: weekStart, sourceType: "assistant_proposal", sourceID: proposalID, occurredAtMS: timestamp)
            let eventContext = MutationContext(id: derivedUUID(from: proposalID, salt: 4), deviceID: context.deviceID, timestamp: timestamp)
            return .init(destination: .weekly(placement, event, eventContext), context: context, target: .init(type: "weekly_work", id: value.actionId, versionID: versionID))
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
            let record = EvidenceRecord(
                id: targetID, goalID: value.goalId, actionID: value.actionId,
                title: value.statement, detail: value.statement,
                occurredAtMS: try milliseconds(value.occurredAt)!, createdAtMS: timestamp
            )
            return .init(destination: .evidence(record), context: context, target: .init(type: "evidence", id: targetID, versionID: versionID))
        case .memory(let delta):
            return try await prepareMemory(
                delta, targetID: targetID, versionID: versionID, context: context
            )
        case .insight(let value):
            let record = InsightRecord(
                id: targetID, body: value.body, status: .reviewNeeded,
                isTimeSensitive: value.isTimeSensitive,
                homeEligibleUntilMS: try milliseconds(value.homeEligibleUntil),
                createdAtMS: timestamp, updatedAtMS: timestamp
            )
            return .init(destination: .insight(record), context: context, target: .init(type: "insight", id: targetID, versionID: versionID))
        }
    }

    private func prepareMemory(
        _ delta: MemoryDelta, targetID: String, versionID: String, context: MutationContext
    ) async throws -> PreparedDestination {
        switch delta {
        case .propose(let candidate, _, _):
            let record = MemoryRecord(
                id: targetID, kind: candidate.type.rawValue, content: candidate.statement,
                status: storageStatus(candidate.lifecycle), createdAtMS: context.timestamp,
                updatedAtMS: context.timestamp
            )
            return .init(destination: .memoryCreate(record), context: context, target: .init(type: "memory", id: targetID, versionID: versionID))
        case .transition(let id, let lifecycle, _, _):
            guard let current = try await memory.get(id: id) else {
                throw AssistantProposalRoutingError.staleTarget
            }
            let record = MemoryRecord(
                id: current.id, kind: current.kind, content: current.content,
                status: storageStatus(lifecycle), createdAtMS: current.createdAtMS,
                updatedAtMS: context.timestamp
            )
            return .init(destination: .memoryUpdate(record), context: context, target: .init(type: "memory", id: current.id, versionID: versionID))
        case .support(let id, let sourceMessageID, _):
            guard try await memory.get(id: id) != nil else {
                throw AssistantProposalRoutingError.staleTarget
            }
            let sourceID = derivedUUID(from: targetID, salt: 3)
            let record = MemorySourceRecord(
                id: sourceID, memoryItemID: id, sourceType: "message",
                sourceID: sourceMessageID, createdAtMS: context.timestamp
            )
            return .init(destination: .memorySource(record), context: context, target: .init(type: "memory_source", id: sourceID, versionID: versionID))
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
        let digest = SHA256.hash(data: Data("\(source.lowercased()):\(salt)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
        return uuid.uuidString
    }
}
