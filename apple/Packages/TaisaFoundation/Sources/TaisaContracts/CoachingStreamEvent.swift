import Foundation

private extension KeyedEncodingContainer where Key == DynamicCodingKey {
    mutating func encode<T: Encodable>(_ value: T, forKey key: String) throws {
        try encode(value, forKey: DynamicCodingKey(stringValue: key)!)
    }
}

public enum CoachingStreamFailureCode: String, Codable, Sendable {
    case coachingUnavailable = "COACHING_UNAVAILABLE"
    case authenticationFailed = "AUTHENTICATION_FAILED"
    case rateLimited = "RATE_LIMITED"
    case costLimitReached = "COST_LIMIT_REACHED"
    case invalidCoachingOutput = "INVALID_COACHING_OUTPUT"
    case incompatibleContract = "INCOMPATIBLE_CONTRACT"
}

public enum CoachingResponseMode: String, Codable, Sendable { case coach, clarify, redirect }
public enum CoachingRelevance: String, Codable, Sendable {
    case careerRelevant = "career-relevant"
    case adjacent
    case outsideScope = "outside-scope"
}
public enum ContextSufficiency: String, Codable, Sendable { case sufficient, partial, insufficient }
public enum CoachingStance: String, Codable, Sendable { case mirror, nudge, challenge, direct }

public enum CoachingConfidence: String, Codable, Sendable { case low, medium, high }
public enum CoachingSourceType: String, Codable, Sendable { case message, goal, action, evidence, memory, insight }
public enum CoachingPriority: String, Codable, Sendable { case low, medium, high }
public enum MemoryType: String, Codable, Sendable {
    case goal, commitment, decision, preference, careerContext = "career_context"
    case developmentArea = "development_area", evidence, pattern
}
public enum MemoryProvenance: String, Codable, Sendable {
    case userStated = "user-stated", userConfirmed = "user-confirmed"
    case aiInferred = "ai-inferred", systemObserved = "system-observed"
}
public enum MemoryLifecycle: String, Codable, Sendable {
    case proposed, active, paused, superseded, completed, rejected, archived
}
public enum MemoryConfidence: String, Codable, Sendable { case tentative, supported, established }

private func isBoundedText(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty && trimmed.count <= 4_000
}

private func isBoundedID(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty && value.count <= 128
}

private func isPortableTimestamp(_ value: String) -> Bool {
    value.count <= 40 && value.range(
        of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$"#,
        options: .regularExpression
    ) != nil
}

public struct CoachingExplanationSource: Equatable, Sendable, Decodable {
    public let sourceId: String
    public let sourceType: CoachingSourceType
    public let excerpt: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        try container.requireOnlyKeys(["sourceId", "sourceType", "excerpt"])
        sourceId = try container.decode(String.self, forKey: "sourceId")
        sourceType = try container.decode(CoachingSourceType.self, forKey: "sourceType")
        excerpt = try container.decode(Optional<String>.self, forKey: "excerpt")
        guard isBoundedID(sourceId), excerpt == nil || isBoundedText(excerpt!) else {
            throw container.invalid("Explanation source must be normalized")
        }
    }
}

public struct CoachingExplanation: Equatable, Sendable, Decodable {
    public let mode: CoachingStance?
    public let evidence: [CoachingExplanationSource]
    public let inference: String
    public let confidence: CoachingConfidence
    public let approach: String

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        try container.requireOnlyKeys(["mode", "evidence", "inference", "confidence", "approach"])
        mode = try container.decode(Optional<CoachingStance>.self, forKey: "mode")
        evidence = try container.decode([CoachingExplanationSource].self, forKey: "evidence")
        inference = try container.decode(String.self, forKey: "inference")
        confidence = try container.decode(CoachingConfidence.self, forKey: "confidence")
        approach = try container.decode(String.self, forKey: "approach")
        guard evidence.count <= 8, isBoundedText(inference), isBoundedText(approach) else {
            throw container.invalid("Explanation metadata is invalid")
        }
    }
}

public struct MemoryCandidate: Equatable, Sendable, Codable {
    public let type: MemoryType
    public let statement: String
    public let provenance: MemoryProvenance
    public let lifecycle: MemoryLifecycle
    public let confidence: MemoryConfidence
    public let sourceMessageIds: [String]
    public let supersedesId: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        try container.requireOnlyKeys(["type", "statement", "provenance", "lifecycle", "confidence", "sourceMessageIds", "supersedesId"])
        type = try container.decode(MemoryType.self, forKey: "type")
        statement = try container.decode(String.self, forKey: "statement")
        provenance = try container.decode(MemoryProvenance.self, forKey: "provenance")
        lifecycle = try container.decode(MemoryLifecycle.self, forKey: "lifecycle")
        confidence = try container.decode(MemoryConfidence.self, forKey: "confidence")
        sourceMessageIds = try container.decode([String].self, forKey: "sourceMessageIds")
        supersedesId = try container.decodeIfPresent(String.self, forKey: "supersedesId")
        guard isBoundedText(statement), sourceMessageIds.count <= 50,
              sourceMessageIds.allSatisfy(isBoundedID),
              supersedesId == nil || isBoundedID(supersedesId!) else {
            throw container.invalid("Memory candidate is invalid")
        }
    }

    enum CodingKeys: String, CodingKey { case type, statement, provenance, lifecycle, confidence, sourceMessageIds, supersedesId }
}

public enum MemoryDelta: Equatable, Sendable, Codable {
    case propose(candidate: MemoryCandidate, reason: String, requiresConfirmation: Bool)
    case transition(targetId: String, to: MemoryLifecycle, reason: String, requiresConfirmation: Bool)
    case support(targetId: String, sourceMessageId: String, reason: String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        switch try container.decode(String.self, forKey: "operation") {
        case "propose":
            try container.requireOnlyKeys(["operation", "candidate", "reason", "requiresConfirmation"])
            let reason = try container.decode(String.self, forKey: "reason")
            guard isBoundedText(reason) else { throw container.invalid("Memory proposal reason is invalid") }
            self = .propose(candidate: try container.decode(MemoryCandidate.self, forKey: "candidate"), reason: reason, requiresConfirmation: try container.decode(Bool.self, forKey: "requiresConfirmation"))
        case "transition":
            try container.requireOnlyKeys(["operation", "targetId", "to", "reason", "requiresConfirmation"])
            let targetId = try container.decode(String.self, forKey: "targetId")
            let reason = try container.decode(String.self, forKey: "reason")
            guard isBoundedID(targetId), isBoundedText(reason) else { throw container.invalid("Memory transition is invalid") }
            self = .transition(targetId: targetId, to: try container.decode(MemoryLifecycle.self, forKey: "to"), reason: reason, requiresConfirmation: try container.decode(Bool.self, forKey: "requiresConfirmation"))
        case "support":
            try container.requireOnlyKeys(["operation", "targetId", "sourceMessageId", "reason", "requiresConfirmation"])
            let targetId = try container.decode(String.self, forKey: "targetId")
            let sourceMessageId = try container.decode(String.self, forKey: "sourceMessageId")
            let reason = try container.decode(String.self, forKey: "reason")
            guard try container.decode(Bool.self, forKey: "requiresConfirmation") == false else {
                throw container.invalid("Memory support must not require confirmation")
            }
            guard isBoundedID(targetId), isBoundedID(sourceMessageId), isBoundedText(reason) else {
                throw container.invalid("Memory support is invalid")
            }
            self = .support(targetId: targetId, sourceMessageId: sourceMessageId, reason: reason)
        default:
            throw container.invalid("Unknown memory operation")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        switch self {
        case let .propose(candidate, reason, requiresConfirmation):
            try container.encode("propose", forKey: "operation"); try container.encode(candidate, forKey: "candidate")
            try container.encode(reason, forKey: "reason"); try container.encode(requiresConfirmation, forKey: "requiresConfirmation")
        case let .transition(targetId, to, reason, requiresConfirmation):
            try container.encode("transition", forKey: "operation"); try container.encode(targetId, forKey: "targetId")
            try container.encode(to, forKey: "to"); try container.encode(reason, forKey: "reason"); try container.encode(requiresConfirmation, forKey: "requiresConfirmation")
        case let .support(targetId, sourceMessageId, reason):
            try container.encode("support", forKey: "operation"); try container.encode(targetId, forKey: "targetId")
            try container.encode(sourceMessageId, forKey: "sourceMessageId"); try container.encode(reason, forKey: "reason")
            try container.encode(false, forKey: "requiresConfirmation")
        }
    }
}

public struct GoalCoachingProposal: Equatable, Sendable, Codable { public let title: String; public let description: String?; public let priority: CoachingPriority?; public let targetDate: String? }
public struct ActionCoachingProposal: Equatable, Sendable, Codable { public let title: String; public let description: String?; public let priority: CoachingPriority?; public let dueAt: String?; public let goalId: String? }
public struct WeeklyWorkCoachingProposal: Equatable, Sendable, Codable { public let actionId: String; public let weekStart: String; public let plannedDay: String? }
public struct EvidenceCoachingProposal: Equatable, Sendable, Codable { public let statement: String; public let occurredAt: String; public let goalId: String?; public let actionId: String? }
public struct InsightCoachingProposal: Equatable, Sendable, Codable { public let body: String; public let isTimeSensitive: Bool; public let homeEligibleUntil: String? }

public enum CoachingProposal: Equatable, Sendable, Codable {
    case goal(GoalCoachingProposal)
    case action(ActionCoachingProposal)
    case weeklyWork(WeeklyWorkCoachingProposal)
    case evidence(EvidenceCoachingProposal)
    case memory(MemoryDelta)
    case insight(InsightCoachingProposal)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        switch try container.decode(String.self, forKey: "kind") {
        case "goal":
            try container.requireOnlyKeys(["kind", "title", "description", "priority", "targetDate"])
            let title = try container.decode(String.self, forKey: "title")
            let description = try container.decode(Optional<String>.self, forKey: "description")
            let targetDate = try container.decode(Optional<String>.self, forKey: "targetDate")
            guard isBoundedText(title), description == nil || isBoundedText(description!),
                  targetDate == nil || isPortableTimestamp(targetDate!) else { throw container.invalid("Goal proposal is invalid") }
            self = .goal(.init(title: title, description: description, priority: try container.decode(Optional<CoachingPriority>.self, forKey: "priority"), targetDate: targetDate))
        case "action":
            try container.requireOnlyKeys(["kind", "title", "description", "priority", "dueAt", "goalId"])
            let title = try container.decode(String.self, forKey: "title")
            let description = try container.decode(Optional<String>.self, forKey: "description")
            let dueAt = try container.decode(Optional<String>.self, forKey: "dueAt")
            let goalId = try container.decode(Optional<String>.self, forKey: "goalId")
            guard isBoundedText(title), description == nil || isBoundedText(description!),
                  dueAt == nil || isPortableTimestamp(dueAt!), goalId == nil || isBoundedID(goalId!) else {
                throw container.invalid("Action proposal is invalid")
            }
            self = .action(.init(title: title, description: description, priority: try container.decode(Optional<CoachingPriority>.self, forKey: "priority"), dueAt: dueAt, goalId: goalId))
        case "weekly_work":
            try container.requireOnlyKeys(["kind", "actionId", "weekStart", "plannedDay"])
            let actionId = try container.decode(String.self, forKey: "actionId")
            let weekStart = try container.decode(String.self, forKey: "weekStart")
            let plannedDay = try container.decode(Optional<String>.self, forKey: "plannedDay")
            guard isBoundedID(actionId), isPortableTimestamp(weekStart),
                  plannedDay == nil || isPortableTimestamp(plannedDay!) else { throw container.invalid("Weekly work proposal is invalid") }
            self = .weeklyWork(.init(actionId: actionId, weekStart: weekStart, plannedDay: plannedDay))
        case "evidence":
            try container.requireOnlyKeys(["kind", "statement", "occurredAt", "goalId", "actionId"])
            let statement = try container.decode(String.self, forKey: "statement")
            let occurredAt = try container.decode(String.self, forKey: "occurredAt")
            let goalId = try container.decode(Optional<String>.self, forKey: "goalId")
            let actionId = try container.decode(Optional<String>.self, forKey: "actionId")
            guard isBoundedText(statement), isPortableTimestamp(occurredAt),
                  goalId == nil || isBoundedID(goalId!), actionId == nil || isBoundedID(actionId!) else {
                throw container.invalid("Evidence proposal is invalid")
            }
            self = .evidence(.init(statement: statement, occurredAt: occurredAt, goalId: goalId, actionId: actionId))
        case "memory":
            try container.requireOnlyKeys(["kind", "memory"])
            self = .memory(try container.decode(MemoryDelta.self, forKey: "memory"))
        case "insight":
            try container.requireOnlyKeys(["kind", "body", "isTimeSensitive", "homeEligibleUntil"])
            let body = try container.decode(String.self, forKey: "body")
            let homeEligibleUntil = try container.decode(Optional<String>.self, forKey: "homeEligibleUntil")
            guard isBoundedText(body), homeEligibleUntil == nil || isPortableTimestamp(homeEligibleUntil!) else {
                throw container.invalid("Insight proposal is invalid")
            }
            self = .insight(.init(body: body, isTimeSensitive: try container.decode(Bool.self, forKey: "isTimeSensitive"), homeEligibleUntil: homeEligibleUntil))
        default:
            throw container.invalid("Unknown coaching proposal kind")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        switch self {
        case .goal(let value): try container.encode("goal", forKey: "kind"); try container.encode(value.title, forKey: "title"); try container.encode(value.description, forKey: "description"); try container.encode(value.priority, forKey: "priority"); try container.encode(value.targetDate, forKey: "targetDate")
        case .action(let value): try container.encode("action", forKey: "kind"); try container.encode(value.title, forKey: "title"); try container.encode(value.description, forKey: "description"); try container.encode(value.priority, forKey: "priority"); try container.encode(value.dueAt, forKey: "dueAt"); try container.encode(value.goalId, forKey: "goalId")
        case .weeklyWork(let value): try container.encode("weekly_work", forKey: "kind"); try container.encode(value.actionId, forKey: "actionId"); try container.encode(value.weekStart, forKey: "weekStart"); try container.encode(value.plannedDay, forKey: "plannedDay")
        case .evidence(let value): try container.encode("evidence", forKey: "kind"); try container.encode(value.statement, forKey: "statement"); try container.encode(value.occurredAt, forKey: "occurredAt"); try container.encode(value.goalId, forKey: "goalId"); try container.encode(value.actionId, forKey: "actionId")
        case .memory(let value): try container.encode("memory", forKey: "kind"); try container.encode(value, forKey: "memory")
        case .insight(let value): try container.encode("insight", forKey: "kind"); try container.encode(value.body, forKey: "body"); try container.encode(value.isTimeSensitive, forKey: "isTimeSensitive"); try container.encode(value.homeEligibleUntil, forKey: "homeEligibleUntil")
        }
    }
}

public struct CoachingResponse: Equatable, Sendable, Decodable {
    public let requestId: UUID
    public let reply: String
    public let mode: CoachingResponseMode
    public let relevance: CoachingRelevance
    public let contextSufficiency: ContextSufficiency
    public let stance: CoachingStance?
    public let explanation: CoachingExplanation
    public let proposal: CoachingProposal?
    public let usage: UsageReceipt
    public let titleSuggestion: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        try container.requireOnlyKeys([
            "requestId", "reply", "mode", "relevance", "contextSufficiency",
            "stance", "explanation", "proposal", "usage", "titleSuggestion",
        ])
        guard let requestId = UUID(uuidString: try container.decode(String.self, forKey: "requestId")) else {
            throw container.invalid("Coaching response request ID must be a UUID")
        }
        self.requestId = requestId
        reply = try container.decode(String.self, forKey: "reply")
        mode = try container.decode(CoachingResponseMode.self, forKey: "mode")
        relevance = try container.decode(CoachingRelevance.self, forKey: "relevance")
        contextSufficiency = try container.decode(ContextSufficiency.self, forKey: "contextSufficiency")
        stance = try container.decodeIfPresent(CoachingStance.self, forKey: "stance")
        explanation = try container.decode(CoachingExplanation.self, forKey: "explanation")
        proposal = try container.decode(Optional<CoachingProposal>.self, forKey: "proposal")
        usage = try container.decode(UsageReceipt.self, forKey: "usage")
        titleSuggestion = try container.decodeIfPresent(String.self, forKey: "titleSuggestion")

        guard !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw container.invalid("Coaching reply must not be empty")
        }
        if let titleSuggestion {
            let trimmed = titleSuggestion.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 80, trimmed == titleSuggestion else {
                throw container.invalid("Conversation title suggestion must be normalized")
            }
        }
        switch mode {
        case .coach:
            guard relevance != .outsideScope, contextSufficiency != .insufficient,
                  stance != nil, explanation.mode == stance else {
                throw container.invalid("Invalid coach response decision")
            }
        case .clarify:
            guard contextSufficiency == .insufficient, stance == nil,
                  explanation.mode == nil, proposal == nil else {
                throw container.invalid("Invalid clarify response decision")
            }
        case .redirect:
            guard relevance == .outsideScope, contextSufficiency != .insufficient,
                  stance == nil, explanation.mode == nil, proposal == nil else {
                throw container.invalid("Invalid redirect response decision")
            }
        }
    }
}

public enum CoachingStreamEvent: Equatable, Sendable, Decodable, StrictStreamEvent {
    case delta(requestId: UUID, sequence: Int, delta: String)
    case completed(requestId: UUID, sequence: Int, response: CoachingResponse, idempotencyReceipt: String)
    case failed(requestId: UUID, sequence: Int, code: CoachingStreamFailureCode, retryable: Bool)

    public var streamRequestID: UUID {
        switch self {
        case let .delta(requestId, _, _), let .completed(requestId, _, _, _), let .failed(requestId, _, _, _): requestId
        }
    }

    public var streamSequence: Int {
        switch self {
        case let .delta(_, sequence, _), let .completed(_, sequence, _, _), let .failed(_, sequence, _, _): sequence
        }
    }

    public var isTerminalStreamEvent: Bool {
        switch self { case .delta: false; case .completed, .failed: true }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let type = try container.decode(String.self, forKey: "type")
        let requestIdValue = try container.decode(String.self, forKey: "requestId")
        let sequence = try container.decode(Int.self, forKey: "sequence")
        let uuidPattern = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"#
        guard requestIdValue.range(of: uuidPattern, options: .regularExpression) != nil,
              let requestId = UUID(uuidString: requestIdValue) else {
            throw container.invalid("Request ID must be a valid UUID")
        }
        guard sequence >= 0 else { throw container.invalid("Sequence must be non-negative") }

        switch type {
        case "coaching.delta":
            try container.requireOnlyKeys(["type", "requestId", "sequence", "delta"])
            let delta = try container.decode(String.self, forKey: "delta")
            guard !delta.isEmpty else { throw container.invalid("Delta must not be empty") }
            self = .delta(requestId: requestId, sequence: sequence, delta: delta)
        case "coaching.completed":
            try container.requireOnlyKeys(["type", "requestId", "sequence", "response", "idempotencyReceipt"])
            let response = try container.decode(CoachingResponse.self, forKey: "response")
            let receipt = try container.decode(String.self, forKey: "idempotencyReceipt")
            guard response.requestId == requestId else { throw container.invalid("Response request ID mismatch") }
            guard !receipt.isEmpty else { throw container.invalid("Idempotency receipt must not be empty") }
            self = .completed(requestId: requestId, sequence: sequence, response: response, idempotencyReceipt: receipt)
        case "coaching.failed":
            try container.requireOnlyKeys(["type", "requestId", "sequence", "code", "retryable"])
            self = .failed(
                requestId: requestId,
                sequence: sequence,
                code: try container.decode(CoachingStreamFailureCode.self, forKey: "code"),
                retryable: try container.decode(Bool.self, forKey: "retryable")
            )
        default:
            throw container.invalid("Unknown coaching event type")
        }
    }
}
