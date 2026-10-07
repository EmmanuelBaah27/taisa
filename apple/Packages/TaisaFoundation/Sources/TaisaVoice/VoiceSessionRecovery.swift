import TaisaStorage

public enum VoiceRecoveryAction: Sendable, Equatable {
    case none
    case retryTranscription
    case retryCoaching
    case reconcileCoaching
    case requireConfirmation
    case cleanupOnly
}

public enum VoiceSessionRecovery {
    public static func action(for record: VoiceTurnRecord) -> VoiceRecoveryAction {
        if record.state == .resumeRequiresConfirmation { return .requireConfirmation }
        if record.stage == .cleanup || record.stage == .finished { return .cleanupOnly }

        switch record.stage {
        case .capture:
            return .none
        case .transcription:
            switch record.state {
            case .queued, .transcribing, .recoverableFailure: return .retryTranscription
            default: return .none
            }
        case .coaching:
            switch record.state {
            case .transcriptClear: return .retryCoaching
            case .coaching, .recoverableFailure: return .reconcileCoaching
            default: return .none
            }
        case .cleanup, .finished:
            return .cleanupOnly
        }
    }
}
