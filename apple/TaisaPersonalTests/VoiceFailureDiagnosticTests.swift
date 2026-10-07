import Foundation
import Testing
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
}
