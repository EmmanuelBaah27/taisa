import Foundation
import Testing
import TaisaStorage
@testable import TaisaVoice

@Suite("Voice session relaunch recovery")
struct VoiceSessionRecoveryTests {
    @Test(arguments: [
        (VoiceTurnState.draft, VoiceTurnStage.capture, VoiceRecoveryAction.none),
        (.queued, .transcription, .retryTranscription),
        (.transcribing, .transcription, .reconcileTranscription),
        (.recoverableFailure, .transcription, .retryTranscription),
        (.transcriptClear, .coaching, .retryCoaching),
        (.coaching, .coaching, .reconcileCoaching),
        (.recoverableFailure, .coaching, .reconcileCoaching),
        (.resumeRequiresConfirmation, .coaching, .requireConfirmation),
        (.resumeRequiresConfirmation, .transcription, .requireConfirmation),
        (.completed, .cleanup, .cleanupOnly),
        (.discarded, .cleanup, .cleanupOnly),
    ])
    func relaunchAtEveryCheckpointResumesOnlyAuthorizedStage(
        state: VoiceTurnState, stage: VoiceTurnStage, expected: VoiceRecoveryAction
    ) {
        let record = VoiceTurnRecord(
            id: UUID().uuidString, conversationID: UUID().uuidString,
            transcriptionRequestID: UUID().uuidString, transcriptionIdempotencyKey: "t",
            coachingRequestID: UUID().uuidString, coachingIdempotencyKey: "c",
            state: state, stage: stage, createdAtMS: 0, updatedAtMS: 0
        )
        #expect(VoiceSessionRecovery.action(for: record) == expected)
    }
}
