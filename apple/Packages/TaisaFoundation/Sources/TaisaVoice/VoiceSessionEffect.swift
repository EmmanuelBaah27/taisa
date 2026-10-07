import TaisaStorage

public enum VoiceSessionEffect: Sendable, Equatable {
    case checkpoint(VoiceTurnRecord)
    case startRecording
    case pauseRecording
    case resumeRecording
    case startTranscription
    case startCoaching
    case requestTranscriptConfirmation
    case requestResumeConfirmation
    case authorizeCoachingRetry
    case authorizeTranscriptionRetry
    case cancelWork
    case deleteAudio(String)
    case completeCleanup
    case conversationReady
}
