import TaisaStorage
import TaisaVoice

enum VoiceSessionDiagnosticAction: String, Equatable, Identifiable {
    case record, pause, resume, send, cancel, discard
    case confirmTranscript, retry, confirmResume, nextTurn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .record: "Record"
        case .pause: "Pause"
        case .resume: "Resume"
        case .send: "Send"
        case .cancel: "Cancel"
        case .discard: "Discard"
        case .confirmTranscript: "Confirm transcript"
        case .retry: "Retry"
        case .confirmResume: "Retry request"
        case .nextTurn: "Next turn"
        }
    }
}
struct VoiceSessionDiagnosticsViewModel: Equatable {
    let state: VoiceTurnState
    let stage: VoiceTurnStage
    let reduceMotion: Bool
    let actionStatusTitle: String?

    init(snapshot: VoiceSessionSnapshot, reduceMotion: Bool, actionStatus: String = "Ready") {
        state = snapshot.durable.state
        stage = snapshot.durable.stage
        self.reduceMotion = reduceMotion
        actionStatusTitle = actionStatus == "Ready" ? nil : actionStatus
    }

    var statusTitle: String {
        switch state {
        case .draft: "Ready to record"
        case .recording: "Recording"
        case .paused: "Recording paused"
        case .queued: "Waiting for a connection"
        case .transcribing: "Transcribing"
        case .transcriptClear: "Transcript ready"
        case .transcriptUncertain, .awaitingTranscriptConfirmation: "Transcript needs confirmation"
        case .coaching: "Preparing coaching"
        case .completed: "Conversation turn complete"
        case .noSpeech: "No speech detected"
        case .recoverableFailure: "Ready to retry"
        case .terminalFailure: "Unable to continue"
        case .cancelled: "Conversation paused"
        case .discarded: "Conversation discarded"
        case .resumeRequiresConfirmation: "Confirm before resuming"
        }
    }

    var statusAccessibilityLabel: String { "Voice session status: \(statusTitle)" }
    var announcesPrivateContent: Bool { false }
    var animatesWaveform: Bool { state == .recording && !reduceMotion }

    var actions: [VoiceSessionDiagnosticAction] {
        switch state {
        case .draft: [.record]
        case .recording: [.pause, .send, .cancel, .discard]
        case .paused: [.resume, .send, .cancel, .discard]
        case .awaitingTranscriptConfirmation, .transcriptUncertain:
            [.confirmTranscript, .cancel, .discard]
        case .recoverableFailure, .cancelled:
            stage == .capture ? [.discard] : [.retry, .cancel, .discard]
        case .resumeRequiresConfirmation: [.confirmResume, .cancel, .discard]
        case .queued, .transcribing, .transcriptClear, .coaching: [.cancel, .discard]
        case .completed, .noSpeech, .terminalFailure, .discarded:
            stage == .finished ? [.nextTurn] : []
        }
    }
}
