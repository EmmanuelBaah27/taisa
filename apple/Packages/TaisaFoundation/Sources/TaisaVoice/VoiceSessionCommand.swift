import Foundation
import TaisaStorage

public struct FinalizedVoiceAudio: Sendable, Equatable {
    public let fileID: String
    public let sha256: String
    public let durationMS: Int64

    public init(fileID: String, sha256: String, durationMS: Int64) {
        self.fileID = fileID; self.sha256 = sha256; self.durationMS = durationMS
    }
}

public enum TranscriptOutcome: Sendable, Equatable {
    case clear(text: String, receipt: String, userMessageID: String)
    case uncertain(text: String, receipt: String)
    case noSpeech(receipt: String)
}

public enum VoiceSessionCommand: Sendable, Equatable {
    case startRecording
    case captureStarted(fileID: String)
    case pauseRecording
    case resumeRecording
    case capturePaused
    case captureFailed(code: String)
    case send(FinalizedVoiceAudio)
    case transcriptionBegan
    case transcriptCompleted(TranscriptOutcome)
    case confirmTranscript(text: String, userMessageID: String)
    case coachingBegan
    case coachingCompleted(receipt: String, assistantMessageID: String)
    case fail(code: String, retryable: Bool, ambiguous: Bool)
    case scheduleRetry(code: String, nextRetryAtMS: Int64)
    case retry
    case restartFailedCoaching(VoiceTurnRecord)
    case confirmResume
    case cancel
    case discard
    case cleanupCompleted
    case beginNextTurn(VoiceTurnRecord)
}
