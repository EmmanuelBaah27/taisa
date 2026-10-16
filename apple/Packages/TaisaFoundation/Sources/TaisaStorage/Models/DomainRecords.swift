import Foundation

public enum ConversationLifecycle: String, Codable, Sendable, CaseIterable {
    case draft, active, completed
}

public enum ConversationInputMode: String, Codable, Sendable, CaseIterable {
    case voice, text
}

public enum TitleAuthority: String, Codable, Sendable, CaseIterable {
    case localFallback, assistantSuggested, user
}

public enum DraftRecoveryKind: String, Codable, Sendable, CaseIterable {
    case saved, recovered, retryableTranscription, retryableCoaching
}

public struct MutationContext: Codable, Sendable, Equatable {
    public let id: String
    public let deviceID: String
    public let timestamp: Int64
    public init(id: String, deviceID: String, timestamp: Int64) {
        self.id = UUIDIdentity.normalizedOrOriginal(id); self.deviceID = UUIDIdentity.normalizedOrOriginal(deviceID); self.timestamp = timestamp
    }
}

public struct ProfileRecord: Codable, Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let headline: String
    public let biography: String
    public let updatedAtMS: Int64
    public init(id: String, displayName: String, headline: String, biography: String, updatedAtMS: Int64) {
        self.id = UUIDIdentity.normalizedOrOriginal(id); self.displayName = displayName; self.headline = headline
        self.biography = biography; self.updatedAtMS = updatedAtMS
    }
}

public struct ConversationRecord: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let lifecycle: ConversationLifecycle
    public let titleAuthority: TitleAuthority
    public let createdAtMS: Int64
    public let updatedAtMS: Int64
    public init(
        id: String,
        title: String,
        lifecycle: ConversationLifecycle = .completed,
        titleAuthority: TitleAuthority = .localFallback,
        createdAtMS: Int64,
        updatedAtMS: Int64
    ) {
        self.id = UUIDIdentity.normalizedOrOriginal(id); self.title = title
        self.lifecycle = lifecycle; self.titleAuthority = titleAuthority
        self.createdAtMS = createdAtMS; self.updatedAtMS = updatedAtMS
    }
}

public struct ConversationDraftRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let conversationID: String
    public let inputMode: ConversationInputMode
    public let text: String?
    public let voiceTurnID: String?
    public let recoveryKind: DraftRecoveryKind
    public let createdAtMS: Int64
    public let updatedAtMS: Int64

    public init(
        id: String,
        conversationID: String,
        inputMode: ConversationInputMode,
        text: String?,
        voiceTurnID: String?,
        recoveryKind: DraftRecoveryKind,
        createdAtMS: Int64,
        updatedAtMS: Int64
    ) {
        self.id = UUIDIdentity.normalizedOrOriginal(id)
        self.conversationID = UUIDIdentity.normalizedOrOriginal(conversationID)
        self.inputMode = inputMode
        self.text = text
        self.voiceTurnID = voiceTurnID.map(UUIDIdentity.normalizedOrOriginal)
        self.recoveryKind = recoveryKind
        self.createdAtMS = createdAtMS
        self.updatedAtMS = updatedAtMS
    }
}

public struct MessageRevisionRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let messageID: String
    public let originalBody: String
    public let replacementMessageID: String?
    public let createdAtMS: Int64

    public init(
        id: String,
        messageID: String,
        originalBody: String,
        replacementMessageID: String?,
        createdAtMS: Int64
    ) {
        self.id = UUIDIdentity.normalizedOrOriginal(id)
        self.messageID = UUIDIdentity.normalizedOrOriginal(messageID)
        self.originalBody = originalBody
        self.replacementMessageID = replacementMessageID.map(UUIDIdentity.normalizedOrOriginal)
        self.createdAtMS = createdAtMS
    }
}

public struct MessageRecord: Codable, Sendable, Equatable {
    public let id: String
    public let conversationID: String
    public let role: String
    public let body: String
    public let createdAtMS: Int64
    public init(id: String, conversationID: String, role: String, body: String, createdAtMS: Int64) {
        self.id = UUIDIdentity.normalizedOrOriginal(id); self.conversationID = UUIDIdentity.normalizedOrOriginal(conversationID); self.role = role; self.body = body
        self.createdAtMS = createdAtMS
    }
}

public enum AssistantResponseMode: String, Codable, Sendable { case coach, clarify, redirect }
public enum AssistantProposalState: String, Codable, Sendable {
    case pending, accepted, dismissed, superseded, stale, unsupported
}
public enum ResponseFeedbackDirection: String, Codable, Sendable {
    case helpful
    case notHelpful = "not_helpful"
}
public enum ResponseQualityFactor: String, Codable, Sendable, CaseIterable, Comparable {
    case evidenceFidelity = "evidence_fidelity"
    case intentAlignment = "intent_alignment"
    case coverage
    case coachingStrategy = "coaching_strategy"
    case insightValue = "insight_value"
    case practicalUtility = "practical_utility"
    case confidenceCalibration = "confidence_calibration"
    case relationalFit = "relational_fit"
    case communicationClarity = "communication_clarity"
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct AssistantResponseMetadataRecord: Codable, Sendable, Equatable {
    public let id: String
    public let responseMessageID: String
    public let requestID: String
    public let idempotencyReceipt: String
    public let mode: AssistantResponseMode
    public let relevance: String
    public let contextSufficiency: String
    public let stance: String?
    public let inference: String
    public let confidence: String
    public let approach: String
    public let createdAtMS: Int64
    public init(responseMessageID: String, requestID: String, idempotencyReceipt: String, mode: AssistantResponseMode, relevance: String, contextSufficiency: String, stance: String?, inference: String, confidence: String, approach: String, createdAtMS: Int64) {
        self.id = UUIDIdentity.normalizedOrOriginal(responseMessageID); self.responseMessageID = UUIDIdentity.normalizedOrOriginal(responseMessageID); self.requestID = UUIDIdentity.normalizedOrOriginal(requestID)
        self.idempotencyReceipt = idempotencyReceipt; self.mode = mode; self.relevance = relevance; self.contextSufficiency = contextSufficiency
        self.stance = stance; self.inference = inference; self.confidence = confidence; self.approach = approach; self.createdAtMS = createdAtMS
    }
}

public struct AssistantResponseSourceRecord: Codable, Sendable, Equatable {
    public let id: String
    public let responseMessageID: String
    public let ordinal: Int
    public let sourceID: String
    public let sourceType: String
    public let excerpt: String?
    public init(id: String, responseMessageID: String, ordinal: Int, sourceID: String, sourceType: String, excerpt: String?) {
        self.id = UUIDIdentity.normalizedOrOriginal(id); self.responseMessageID = UUIDIdentity.normalizedOrOriginal(responseMessageID)
        self.ordinal = ordinal; self.sourceID = sourceID; self.sourceType = sourceType; self.excerpt = excerpt
    }
}

public struct AssistantProposalRecord: Codable, Sendable, Equatable {
    public let id: String
    public let responseMessageID: String
    public let kind: String
    public let canonicalPayload: Data
    public let payloadDigest: String
    public let state: AssistantProposalState
    public let targetType: String?
    public let targetID: String?
    public let targetVersionID: String?
    public let decisionReceipt: String?
    public let createdAtMS: Int64
    public let resolvedAtMS: Int64?
    public init(id: String, responseMessageID: String, kind: String, canonicalPayload: Data, payloadDigest: String, state: AssistantProposalState, targetType: String?, targetID: String?, targetVersionID: String?, decisionReceipt: String?, createdAtMS: Int64, resolvedAtMS: Int64?) {
        self.id = UUIDIdentity.normalizedOrOriginal(id); self.responseMessageID = UUIDIdentity.normalizedOrOriginal(responseMessageID); self.kind = kind
        self.canonicalPayload = canonicalPayload; self.payloadDigest = payloadDigest; self.state = state; self.targetType = targetType
        self.targetID = targetID; self.targetVersionID = targetVersionID; self.decisionReceipt = decisionReceipt; self.createdAtMS = createdAtMS; self.resolvedAtMS = resolvedAtMS
    }
}

public struct ResponseFeedbackRecord: Codable, Sendable, Equatable {
    public let responseMessageID: String
    public let direction: ResponseFeedbackDirection
    public let factors: [ResponseQualityFactor]
    public let detail: String?
    public let updatedAtMS: Int64
    public init(responseMessageID: String, direction: ResponseFeedbackDirection, factors: [ResponseQualityFactor], detail: String?, updatedAtMS: Int64) {
        self.responseMessageID = UUIDIdentity.normalizedOrOriginal(responseMessageID); self.direction = direction
        self.factors = Array(Set(factors)).sorted(); self.detail = detail; self.updatedAtMS = updatedAtMS
    }
}

public struct ResponsePreferenceSignalRecord: Codable, Sendable, Equatable {
    public let factor: ResponseQualityFactor
    public let direction: ResponseFeedbackDirection
    public init(factor: ResponseQualityFactor, direction: ResponseFeedbackDirection) {
        self.factor = factor
        self.direction = direction
    }
}

public struct AssistantResponseRecord: Codable, Sendable, Equatable {
    public let metadata: AssistantResponseMetadataRecord
    public let sources: [AssistantResponseSourceRecord]
    public let proposal: AssistantProposalRecord?
    public let feedback: ResponseFeedbackRecord?
}

public struct AssistantResponseWrite: Sendable, Equatable {
    public let message: MessageRecord
    public let metadata: AssistantResponseMetadataRecord
    public let sources: [AssistantResponseSourceRecord]
    public let proposal: AssistantProposalRecord?
    public init(message: MessageRecord, metadata: AssistantResponseMetadataRecord, sources: [AssistantResponseSourceRecord], proposal: AssistantProposalRecord?) {
        self.message = message; self.metadata = metadata; self.sources = sources; self.proposal = proposal
    }
}

public struct GoalRecord: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let detail: String
    public let status: String
    public let createdAtMS: Int64
    public let updatedAtMS: Int64
    public init(id: String, title: String, detail: String, status: String, createdAtMS: Int64, updatedAtMS: Int64) {
        self.id = UUIDIdentity.normalizedOrOriginal(id); self.title = title; self.detail = detail; self.status = status
        self.createdAtMS = createdAtMS; self.updatedAtMS = updatedAtMS
    }
}

public struct MilestoneRecord: Codable, Sendable, Equatable {
    public let id: String
    public let goalID: String
    public let title: String
    public let status: String
    public let targetAtMS: Int64?
    public let updatedAtMS: Int64
    public init(id: String, goalID: String, title: String, status: String, targetAtMS: Int64?, updatedAtMS: Int64) {
        self.id = UUIDIdentity.normalizedOrOriginal(id); self.goalID = UUIDIdentity.normalizedOrOriginal(goalID); self.title = title; self.status = status
        self.targetAtMS = targetAtMS; self.updatedAtMS = updatedAtMS
    }
}

public struct ActionRecord: Codable, Sendable, Equatable {
    public let id: String
    public let goalID: String?
    public let title: String
    public let detail: String
    public let status: String
    public let dueAtMS: Int64?
    public let createdAtMS: Int64
    public let updatedAtMS: Int64
    public init(id: String, goalID: String?, title: String, detail: String, status: String, dueAtMS: Int64?, createdAtMS: Int64, updatedAtMS: Int64) {
        self.id = UUIDIdentity.normalizedOrOriginal(id); self.goalID = goalID.map(UUIDIdentity.normalizedOrOriginal); self.title = title; self.detail = detail; self.status = status
        self.dueAtMS = dueAtMS; self.createdAtMS = createdAtMS; self.updatedAtMS = updatedAtMS
    }
}

public struct EvidenceRecord: Codable, Sendable, Equatable {
    public let id: String
    public let goalID: String?
    public let actionID: String?
    public let title: String
    public let detail: String
    public let occurredAtMS: Int64
    public let createdAtMS: Int64
    public init(id: String, goalID: String?, actionID: String?, title: String, detail: String, occurredAtMS: Int64, createdAtMS: Int64) {
        self.id = UUIDIdentity.normalizedOrOriginal(id); self.goalID = goalID.map(UUIDIdentity.normalizedOrOriginal); self.actionID = actionID.map(UUIDIdentity.normalizedOrOriginal); self.title = title; self.detail = detail
        self.occurredAtMS = occurredAtMS; self.createdAtMS = createdAtMS
    }
}

public struct MemoryRecord: Codable, Sendable, Equatable {
    public let id: String
    public let kind: String
    public let content: String
    public let status: String
    public let createdAtMS: Int64
    public let updatedAtMS: Int64
    public init(id: String, kind: String, content: String, status: String, createdAtMS: Int64, updatedAtMS: Int64) {
        self.id = UUIDIdentity.normalizedOrOriginal(id); self.kind = kind; self.content = content; self.status = status
        self.createdAtMS = createdAtMS; self.updatedAtMS = updatedAtMS
    }
}

public struct MemorySourceRecord: Codable, Sendable, Equatable {
    public let id: String
    public let memoryItemID: String
    public let sourceType: String
    public let sourceID: String
    public let createdAtMS: Int64
    public init(id: String, memoryItemID: String, sourceType: String, sourceID: String, createdAtMS: Int64) {
        self.id = UUIDIdentity.normalizedOrOriginal(id); self.memoryItemID = UUIDIdentity.normalizedOrOriginal(memoryItemID); self.sourceType = sourceType
        self.sourceID = UUIDIdentity.normalizedOrOriginal(sourceID); self.createdAtMS = createdAtMS
    }
}

public enum WorkEventKind: String, Codable, Sendable, CaseIterable {
    case created, placed, moved, completed, restored, removed
}

public enum InsightStatus: String, Codable, Sendable, CaseIterable {
    case confirmed
    case reviewNeeded = "review_needed"
    case superseded, retired
}

public enum InsightRevisionStatus: String, Codable, Sendable, CaseIterable {
    case proposed, accepted, rejected
}

public struct WeeklyPlacementRecord: Codable, Sendable, Equatable {
    public let id: String
    public let actionID: String
    public let weekStartMS: Int64
    public let plannedDayMS: Int64?
    public let createdAtMS: Int64
    public let updatedAtMS: Int64
    public init(id: String, actionID: String, weekStartMS: Int64, plannedDayMS: Int64?, createdAtMS: Int64, updatedAtMS: Int64) {
        self.id = UUIDIdentity.normalizedOrOriginal(id); self.actionID = UUIDIdentity.normalizedOrOriginal(actionID)
        self.weekStartMS = weekStartMS; self.plannedDayMS = plannedDayMS; self.createdAtMS = createdAtMS; self.updatedAtMS = updatedAtMS
    }
}

public struct WorkEventRecord: Codable, Sendable, Equatable {
    public let id: String
    public let actionID: String
    public let kind: WorkEventKind
    public let fromWeekStartMS: Int64?
    public let toWeekStartMS: Int64?
    public let sourceType: String
    public let sourceID: String?
    public let occurredAtMS: Int64
    public init(id: String, actionID: String, kind: WorkEventKind, fromWeekStartMS: Int64?, toWeekStartMS: Int64?, sourceType: String, sourceID: String?, occurredAtMS: Int64) {
        self.id = UUIDIdentity.normalizedOrOriginal(id); self.actionID = UUIDIdentity.normalizedOrOriginal(actionID); self.kind = kind
        self.fromWeekStartMS = fromWeekStartMS; self.toWeekStartMS = toWeekStartMS; self.sourceType = sourceType
        self.sourceID = sourceID.map(UUIDIdentity.normalizedOrOriginal); self.occurredAtMS = occurredAtMS
    }
}

public struct InsightRecord: Sendable, Equatable, Codable {
    public let id: String
    public let body: String
    public let status: InsightStatus
    public let isTimeSensitive: Bool
    public let homeEligibleUntilMS: Int64?
    public let createdAtMS: Int64
    public let updatedAtMS: Int64
    public init(id: String, body: String, status: InsightStatus, isTimeSensitive: Bool, homeEligibleUntilMS: Int64?, createdAtMS: Int64, updatedAtMS: Int64) {
        self.id = UUIDIdentity.normalizedOrOriginal(id); self.body = body; self.status = status; self.isTimeSensitive = isTimeSensitive
        self.homeEligibleUntilMS = homeEligibleUntilMS; self.createdAtMS = createdAtMS; self.updatedAtMS = updatedAtMS
    }
    enum CodingKeys: String, CodingKey { case id, body, status, isTimeSensitive, homeEligibleUntilMS, createdAtMS, updatedAtMS }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(String.self, forKey: .id),
            body: try values.decode(String.self, forKey: .body),
            status: try values.decode(InsightStatus.self, forKey: .status),
            isTimeSensitive: try values.decode(Int64.self, forKey: .isTimeSensitive) == 1,
            homeEligibleUntilMS: try values.decodeIfPresent(Int64.self, forKey: .homeEligibleUntilMS),
            createdAtMS: try values.decode(Int64.self, forKey: .createdAtMS),
            updatedAtMS: try values.decode(Int64.self, forKey: .updatedAtMS)
        )
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id); try values.encode(body, forKey: .body); try values.encode(status, forKey: .status)
        try values.encode(isTimeSensitive ? Int64(1) : Int64(0), forKey: .isTimeSensitive)
        try values.encodeIfPresent(homeEligibleUntilMS, forKey: .homeEligibleUntilMS)
        try values.encode(createdAtMS, forKey: .createdAtMS); try values.encode(updatedAtMS, forKey: .updatedAtMS)
    }
}

public struct InsightSourceRecord: Codable, Sendable, Equatable {
    public let id: String
    public let insightID: String
    public let sourceType: String
    public let sourceID: String
    public let excerpt: String
    public let createdAtMS: Int64
    public init(id: String, insightID: String, sourceType: String, sourceID: String, excerpt: String, createdAtMS: Int64) {
        self.id = UUIDIdentity.normalizedOrOriginal(id); self.insightID = UUIDIdentity.normalizedOrOriginal(insightID)
        self.sourceType = sourceType; self.sourceID = UUIDIdentity.normalizedOrOriginal(sourceID); self.excerpt = excerpt; self.createdAtMS = createdAtMS
    }
}

public struct InsightRevisionRecord: Codable, Sendable, Equatable {
    public let id: String
    public let insightID: String?
    public let proposedBody: String
    public let status: InsightRevisionStatus
    public let sourceType: String
    public let sourceID: String?
    public let createdAtMS: Int64
    public let resolvedAtMS: Int64?
    public init(id: String, insightID: String?, proposedBody: String, status: InsightRevisionStatus, sourceType: String, sourceID: String?, createdAtMS: Int64, resolvedAtMS: Int64?) {
        self.id = UUIDIdentity.normalizedOrOriginal(id); self.insightID = insightID.map(UUIDIdentity.normalizedOrOriginal); self.proposedBody = proposedBody
        self.status = status; self.sourceType = sourceType; self.sourceID = sourceID.map(UUIDIdentity.normalizedOrOriginal)
        self.createdAtMS = createdAtMS; self.resolvedAtMS = resolvedAtMS
    }
}
