import SwiftUI
import TaisaPreviewSupport
import TaisaStorage
import TaisaVoice

@MainActor
enum VoiceSessionScenarios {
    static var scenarios: [PreviewScenario] {
        var result: [PreviewScenario] = []
        for fixture in VoiceSessionFixtures.all {
            result.append(makeFixture(fixture))
        }
        result.append(contentsOf: [
            make(
                identifier: "voice.accessibility",
                title: "Voice accessibility text",
                accessibility: .init(contentSize: .accessibilityExtraExtraExtraLarge),
                reduceMotion: false
            ),
            make(
                identifier: "voice.reducedMotion",
                title: "Voice reduced motion",
                accessibility: .init(reducedMotion: true),
                reduceMotion: true
            ),
        ])
        return result
    }

    private static func makeFixture(_ fixture: VoiceSessionFixture) -> PreviewScenario {
        PreviewScenario(
            identifier: fixture.identifier,
            title: fixture.identifier
                .replacingOccurrences(of: "voice.", with: "Voice ")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized,
            deviceFamily: .adaptive,
            accessibility: .default,
            readiness: .ready
        ) {
            AnyView(VoiceSessionDiagnosticsView(snapshot: snapshot(for: fixture)))
        }
    }

    private static func make(
        identifier: String,
        title: String,
        accessibility: PreviewAccessibilitySettings,
        reduceMotion: Bool
    ) -> PreviewScenario {
        PreviewScenario(
            identifier: identifier,
            title: title,
            deviceFamily: .adaptive,
            accessibility: accessibility,
            readiness: .ready
        ) {
            AnyView(
                VoiceSessionDiagnosticsView(
                    snapshot: recordingSnapshot,
                    reduceMotionOverride: reduceMotion
                )
            )
        }
    }

    private static var recordingSnapshot: VoiceSessionSnapshot {
        VoiceSessionSnapshot(
            durable: VoiceTurnRecord(
                id: "11111111-1111-4111-8111-111111111111",
                conversationID: "22222222-2222-4222-8222-222222222222",
                transcriptionRequestID: "33333333-3333-4333-8333-333333333333",
                transcriptionIdempotencyKey: "synthetic-transcription-v1",
                coachingRequestID: "44444444-4444-4444-8444-444444444444",
                coachingIdempotencyKey: "synthetic-coaching-v1",
                state: .recording, stage: .capture,
                createdAtMS: 1_796_080_000_000, updatedAtMS: 1_796_080_000_000
            ),
            partialTranscript: "",
            partialCoaching: ""
        )
    }

    private static func snapshot(for fixture: VoiceSessionFixture) -> VoiceSessionSnapshot {
        let state = VoiceTurnState(rawValue: fixture.state) ?? .terminalFailure
        let stage = VoiceTurnStage(rawValue: fixture.stage) ?? .finished
        return VoiceSessionSnapshot(
            durable: VoiceTurnRecord(
                id: "11111111-1111-4111-8111-111111111111",
                conversationID: "22222222-2222-4222-8222-222222222222",
                transcriptionRequestID: "33333333-3333-4333-8333-333333333333",
                transcriptionIdempotencyKey: "synthetic-transcription-v1",
                coachingRequestID: "44444444-4444-4444-8444-444444444444",
                coachingIdempotencyKey: "synthetic-coaching-v1",
                state: state,
                stage: stage,
                createdAtMS: fixture.timestampMS,
                updatedAtMS: fixture.timestampMS
            ),
            partialTranscript: "",
            partialCoaching: ""
        )
    }
}
