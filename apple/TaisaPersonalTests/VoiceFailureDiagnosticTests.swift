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

    @Test func systemCaptureUsesConversationalInputConfiguration() {
        #expect(SystemAudioSessionAdapter.captureCategory == .playAndRecord)
        #expect(SystemAudioSessionAdapter.captureMode == .voiceChat)
    }
}
