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
