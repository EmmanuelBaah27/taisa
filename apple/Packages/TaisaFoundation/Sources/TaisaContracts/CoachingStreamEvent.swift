import Foundation

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

public enum JSONValue: Equatable, Sendable, Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }
}

public struct CoachingResponse: Equatable, Sendable, Decodable {
    public let requestId: UUID
    public let reply: String
    public let mode: CoachingResponseMode
    public let relevance: CoachingRelevance
    public let contextSufficiency: ContextSufficiency
    public let stance: CoachingStance?
    public let proposals: [JSONValue]
    public let usage: UsageReceipt
    public let titleSuggestion: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        try container.requireOnlyKeys([
            "requestId", "reply", "mode", "relevance", "contextSufficiency",
            "stance", "proposals", "usage", "titleSuggestion",
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
        proposals = try container.decode([JSONValue].self, forKey: "proposals")
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
            guard relevance != .outsideScope, contextSufficiency != .insufficient, stance != nil else {
                throw container.invalid("Invalid coach response decision")
            }
        case .clarify:
            guard contextSufficiency == .insufficient, stance == nil, proposals.isEmpty else {
                throw container.invalid("Invalid clarify response decision")
            }
        case .redirect:
            guard relevance == .outsideScope, contextSufficiency != .insufficient,
                  stance == nil, proposals.isEmpty else {
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
