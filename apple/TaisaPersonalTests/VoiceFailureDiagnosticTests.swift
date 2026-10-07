import Foundation
import Testing
import AVFAudio
import TaisaAudio
@testable import TaisaPersonal

@Suite struct VoiceFailureDiagnosticTests {
    @Test func actionFailureReportsOnlyErrorDomainAndCode() {
        let error = NSError(
            domain: NSOSStatusErrorDomain,
            code: -50,
            userInfo: [NSLocalizedDescriptionKey: "PRIVATE /var/mobile/path"]
        )

        #expect(voiceActionFailureStatus(error) == "Voice action failed (NSOSStatusErrorDomain -50).")
    }

    @Test(arguments: [
        (AudioCaptureError.permissionDenied, "CAPTURE_PERMISSION_DENIED"),
        (AudioCaptureError.noActiveCapture, "CAPTURE_NO_ACTIVE_CAPTURE"),
        (AudioCaptureError.invalidState, "CAPTURE_INVALID_STATE"),
        (AudioCaptureError.audioNotFinalized, "CAPTURE_AUDIO_NOT_FINALIZED"),
        (AudioCaptureError.unsupportedPlatform, "CAPTURE_UNSUPPORTED_PLATFORM"),
    ])
    func actionFailureReportsStableAudioCaptureCode(
        error: AudioCaptureError,
        expected: String
    ) {
        #expect(voiceActionFailureStatus(error) == "Voice action failed (\(expected)).")
    }

    @Test func actionFailureReportsOwnedTurnMismatchWithoutIdentifiers() {
        let error = AudioCaptureError.turnAlreadyOwned(expected: UUID(), received: UUID())

        #expect(
            voiceActionFailureStatus(error)
                == "Voice action failed (CAPTURE_TURN_ALREADY_OWNED)."
        )
    }

    @Test func systemCaptureUsesConversationalInputConfiguration() {
        #expect(SystemAudioSessionAdapter.captureCategory == .playAndRecord)
        #expect(SystemAudioSessionAdapter.captureMode == .voiceChat)
    }
}
