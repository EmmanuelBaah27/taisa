import Foundation
import Testing
@testable import TaisaPreviewSupport

@Suite("Voice session fixtures")
struct VoiceSessionFixtureTests {
    @Test("registry covers every platform validation state with stable identifiers")
    func registryCoversRequiredStates() {
        let fixtures = VoiceSessionFixtures.all
        #expect(Set(fixtures.map(\.identifier)) == [
            "voice.clear", "voice.uncertain", "voice.no-speech", "voice.offline",
            "voice.reconnecting", "voice.interrupted", "voice.ambiguous",
            "voice.failed", "voice.completed", "voice.second-turn",
        ])
        #expect(Set(fixtures.map(\.identifier)).count == fixtures.count)
    }

    @Test("fixtures encode only content-free deterministic evidence")
    func fixturesAreContentFreeAndDeterministic() throws {
        let first = try JSONEncoder.sorted.encode(VoiceSessionFixtures.all)
        let second = try JSONEncoder.sorted.encode(VoiceSessionFixtures.all)
        #expect(first == second)

        let text = String(decoding: first, as: UTF8.self)
        for forbidden in [
            "\"transcript\":", "\"response\":", "audioPath", "file://", "/private/",
            "\"context\":", "acceptedTranscript", "uncertainTranscript",
        ] {
            #expect(!text.localizedCaseInsensitiveContains(forbidden))
        }
        #expect(VoiceSessionFixtures.all.allSatisfy { !$0.fingerprint.isEmpty })
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
