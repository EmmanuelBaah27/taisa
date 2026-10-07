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
