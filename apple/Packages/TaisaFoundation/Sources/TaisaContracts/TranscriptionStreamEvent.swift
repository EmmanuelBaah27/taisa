import Foundation

public enum TranscriptionQuality: String, Codable, Sendable {
    case clear
    case uncertain
}

public enum UsageProvider: String, Codable, Sendable {
    case anthropic
    case openai
}

public struct UsageReceipt: Equatable, Sendable, Decodable {
    public let provider: UsageProvider
    public let model: String
    public let inputTokens: Double?
    public let outputTokens: Double?
    public let audioSeconds: Double?
    public let estimatedCostUsd: Double

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        try container.requireOnlyKeys([
            "provider", "model", "inputTokens", "outputTokens", "audioSeconds",
            "estimatedCostUsd",
        ])
        provider = try container.decode(UsageProvider.self, forKey: "provider")
        model = try container.decode(String.self, forKey: "model")
        inputTokens = try container.decodeOptionalNumber(forKey: "inputTokens")
        outputTokens = try container.decodeOptionalNumber(forKey: "outputTokens")
        audioSeconds = try container.decodeOptionalNumber(forKey: "audioSeconds")
        estimatedCostUsd = try container.decode(Double.self, forKey: "estimatedCostUsd")

        guard !model.isEmpty else { throw container.invalid("Usage model must not be empty") }
        for value in [inputTokens, outputTokens, audioSeconds].compactMap({ $0 }) {
            guard value.isFinite, value >= 0 else {
                throw container.invalid("Usage counts must be finite and non-negative")
            }
        }
        guard estimatedCostUsd.isFinite, estimatedCostUsd >= 0 else {
            throw container.invalid("Estimated cost must be finite and non-negative")
        }
    }
}

public enum TranscriptionStreamEvent: Equatable, Sendable, Decodable {
    case delta(requestId: UUID, sequence: Int, delta: String)
    case completed(
        requestId: UUID,
        sequence: Int,
        transcript: String,
        durationSeconds: Double,
        quality: TranscriptionQuality,
        usage: UsageReceipt
    )
    case noSpeech(requestId: UUID, sequence: Int)
    case failed(requestId: UUID, sequence: Int)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let type = try container.decode(String.self, forKey: "type")
        let envelope = try Self.decodeEnvelope(from: container)

        switch type {
        case "transcript.delta":
            try container.requireOnlyKeys(["type", "requestId", "sequence", "delta"])
            self = .delta(
                requestId: envelope.requestId,
                sequence: envelope.sequence,
                delta: try container.decode(String.self, forKey: "delta")
            )
        case "transcript.completed":
            try container.requireOnlyKeys([
                "type", "requestId", "sequence", "transcript", "durationSeconds",
                "quality", "usage",
            ])
            let transcript = try container.decode(String.self, forKey: "transcript")
            let duration = try container.decode(Double.self, forKey: "durationSeconds")
            guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw container.invalid("Completed transcript must not be empty")
            }
            guard duration.isFinite, duration > 0 else {
                throw container.invalid("Duration must be finite and positive")
            }
            self = .completed(
                requestId: envelope.requestId,
                sequence: envelope.sequence,
                transcript: transcript,
                durationSeconds: duration,
                quality: try container.decode(TranscriptionQuality.self, forKey: "quality"),
                usage: try container.decode(UsageReceipt.self, forKey: "usage")
            )
        case "transcript.no_speech":
            try container.requireOnlyKeys(["type", "requestId", "sequence"])
            self = .noSpeech(requestId: envelope.requestId, sequence: envelope.sequence)
        case "transcript.failed":
            try container.requireOnlyKeys(["type", "requestId", "sequence", "code"])
            let code = try container.decode(String.self, forKey: "code")
            guard code == "TRANSCRIPTION_FAILED" else {
                throw container.invalid("Unknown transcription failure code")
            }
            self = .failed(requestId: envelope.requestId, sequence: envelope.sequence)
        default:
            throw container.invalid("Unknown transcription event type")
        }
    }

    private static func decodeEnvelope(
        from container: KeyedDecodingContainer<DynamicCodingKey>
    ) throws -> (requestId: UUID, sequence: Int) {
        let requestIdValue = try container.decode(String.self, forKey: "requestId")
        let sequence = try container.decode(Int.self, forKey: "sequence")
        let pattern = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"#
        guard requestIdValue.range(of: pattern, options: .regularExpression) != nil,
              let requestId = UUID(uuidString: requestIdValue) else {
            throw container.invalid("Request ID must be a valid UUID")
        }
        guard sequence >= 0 else { throw container.invalid("Sequence must be non-negative") }
        return (requestId, sequence)
    }
}

struct DynamicCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

extension KeyedDecodingContainer where Key == DynamicCodingKey {
    func decode<T: Decodable>(_ type: T.Type, forKey key: String) throws -> T {
        try decode(type, forKey: DynamicCodingKey(stringValue: key)!)
    }

    func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: String) throws -> T? {
        try decodeIfPresent(type, forKey: DynamicCodingKey(stringValue: key)!)
    }

    func decodeOptionalNumber(forKey key: String) throws -> Double? {
        let codingKey = DynamicCodingKey(stringValue: key)!
        guard contains(codingKey) else { return nil }
        return try decode(Double.self, forKey: codingKey)
    }

    func requireOnlyKeys(_ allowed: Set<String>) throws {
        let actual = Set(allKeys.map(\.stringValue))
        guard actual.isSubset(of: allowed) else {
            throw invalid("Unexpected event fields: \(actual.subtracting(allowed).sorted())")
        }
    }

    func requireOnlyKeys(_ allowed: [String]) throws {
        try requireOnlyKeys(Set(allowed))
    }

    func invalid(_ message: String) -> DecodingError {
        .dataCorrupted(.init(codingPath: codingPath, debugDescription: message))
    }
}
