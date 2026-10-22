import SwiftUI
import TaisaDesignSystem
import TaisaPreviewSupport

@MainActor
enum RecordingGlowScenarios {
    static let scenarios: [PreviewScenario] = [
        glow("silent", "Recording glow · silent", loudness: 0),
        glow("low", "Recording glow · low", loudness: 0.18),
        glow("conversational", "Recording glow · conversational", loudness: 0.52),
        glow("peak", "Recording glow · peak", loudness: 1),
        glow("paused", "Recording glow · paused", loudness: 0.52, state: .paused),
        glow("reduce-motion", "Recording glow · reduce motion", loudness: 0.52, state: .reduceMotion, reducedMotion: true),
        glow("reduced-transparency", "Recording glow · reduced transparency", loudness: 0.52, state: .reducedTransparency),
        PreviewScenario(
            identifier: "recording-glow.tuner",
            title: "Recording glow · tuning lab",
            deviceFamily: .adaptive,
            accessibility: .default,
            readiness: .ready
        ) { AnyView(RecordingGlowTuningView()) },
    ]

    private static func glow(
        _ suffix: String,
        _ title: String,
        loudness: Double,
        state: RecordingGlowState = .recording,
        reducedMotion: Bool = false
    ) -> PreviewScenario {
        PreviewScenario(
            identifier: "recording-glow.\(suffix)",
            title: title,
            deviceFamily: .adaptive,
            accessibility: .init(reducedMotion: reducedMotion),
            readiness: .ready
        ) {
            AnyView(
                RecordingGlowScenarioView(
                    title: title,
                    loudness: loudness,
                    state: state
                )
            )
        }
    }
}

private struct RecordingGlowScenarioView: View {
    let title: String
    let loudness: Double
    let state: RecordingGlowState

    var body: some View {
        VStack(alignment: .leading, spacing: TaisaSpacing.section.rawValue) {
            TaisaText(role: .heading, content: title)
            TaisaText(
                role: .metadata,
                color: .mutedForeground,
                content: "Deterministic loudness: \(loudness.formatted(.number.precision(.fractionLength(2))))"
            )
            RecordingReactiveGlow(loudness: loudness, state: state)
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Recording glow preview")
                .accessibilityIdentifier("recording-glow.surface")
        }
        .padding(TaisaSpacing.page.rawValue)
    }
}
