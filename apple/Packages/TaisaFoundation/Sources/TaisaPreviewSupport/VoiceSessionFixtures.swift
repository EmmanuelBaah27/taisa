import Foundation

public struct VoiceSessionFixture: Codable, Sendable, Equatable, Identifiable {
    public let identifier: String
    public let state: String
    public let stage: String
    public let eventCount: Int
    public let byteCount: Int
    public let durationMS: Int64
    public let sequence: Int
    public let fingerprint: String
    public let timestampMS: Int64

    public var id: String { identifier }
}

/// Synthetic, network-denied scenario metadata. It deliberately cannot carry
/// transcript, coaching, private context, or local file-location fields.
public enum VoiceSessionFixtures {
    public static let all: [VoiceSessionFixture] = [
        fixture("voice.clear", state: "transcriptClear", stage: "coaching", events: 3),
        fixture("voice.uncertain", state: "awaitingTranscriptConfirmation", stage: "transcription", events: 3),
        fixture("voice.no-speech", state: "noSpeech", stage: "cleanup", events: 1),
        fixture("voice.offline", state: "queued", stage: "transcription", events: 0),
        fixture("voice.reconnecting", state: "transcribing", stage: "transcription", events: 1),
        fixture("voice.interrupted", state: "paused", stage: "capture", events: 0),
        fixture("voice.ambiguous", state: "resumeRequiresConfirmation", stage: "coaching", events: 2),
        fixture("voice.failed", state: "recoverableFailure", stage: "coaching", events: 2),
        fixture("voice.completed", state: "completed", stage: "cleanup", events: 4),
        fixture("voice.second-turn", state: "draft", stage: "capture", events: 4),
    ]

    private static func fixture(
        _ identifier: String,
        state: String,
        stage: String,
        events: Int
    ) -> VoiceSessionFixture {
        VoiceSessionFixture(
            identifier: identifier,
            state: state,
            stage: stage,
            eventCount: events,
            byteCount: events * 1_024,
            durationMS: Int64(events * 1_000),
            sequence: events,
            fingerprint: "synthetic-\(identifier)-v1",
            timestampMS: 1_796_080_000_000
        )
    }
}
