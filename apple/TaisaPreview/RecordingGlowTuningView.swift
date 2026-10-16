import SwiftUI
import TaisaAudio
import TaisaDesignSystem
import UIKit

struct RecordingGlowTuningView: View {
    @State private var preset = RecordingGlowPreset.figmaDefault
    @State private var response = LoudnessEnvelopeConfiguration()
    @State private var loudness = 0.52
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: TaisaSpacing.section.rawValue) {
            RecordingReactiveGlow(loudness: loudness, state: .recording, preset: preset)
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Recording glow preview")
                .accessibilityIdentifier("recording-glow.surface")

            section("Input") {
                slider("Simulated loudness", value: $loudness)
                slider("Input gain", value: $response.inputGain, range: 0...2)
                slider("Response curve", value: $response.responseExponent, range: 0.2...2)
                slider("Attack seconds", value: $response.attackSeconds, range: 0.02...0.6)
                slider("Release seconds", value: $response.releaseSeconds, range: 0.1...1.5)
            }

            section("Center") {
                slider("Center baseline height", value: $preset.centerBaselineHeight)
                slider("Center peak height", value: $preset.centerPeakHeight)
                slider("Center width", value: $preset.centerWidth)
                slider("Center bloom", value: $preset.centerBloom)
                slider("Center strength", value: $preset.center.strength)
                color("Dominant center purple color", value: $preset.center.color)
            }

            section("Supporting edges") {
                slider("Edge gain", value: $preset.edgeGain)
                slider("Edge spread", value: $preset.edgeSpread)
                slider("Edge softness", value: $preset.edgeSoftness)
                slider("Edge balance", value: $preset.edgeBalance)
                color("Left outer yellow color", value: $preset.leftOuter.color)
                color("Left inner blue color", value: $preset.leftInner.color)
                color("Right inner coral color", value: $preset.rightInner.color)
                color("Right outer green color", value: $preset.rightOuter.color)
            }

            section("Grain and composition") {
                slider("Grain amount", value: $preset.grain.amount)
                slider("Grain scale", value: $preset.grain.scale)
                slider("Grain contrast", value: $preset.grain.contrast)
                slider("Grain softness", value: $preset.grain.softness)
                slider("Grain loudness influence", value: $preset.grain.loudnessInfluence)
                slider("Global opacity", value: $preset.globalOpacity)
                slider("Vertical origin", value: $preset.verticalOrigin)
            }

            HStack {
                Button("Reset to Figma preset") { reset() }
                Button("Copy preset JSON") { copyJSON() }
            }
            .buttonStyle(.bordered)
            if copied { Text("Copied").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(TaisaSpacing.page.rawValue)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: TaisaSpacing.standard.rawValue) {
            Text(title).font(.headline)
            content()
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double> = 0...1) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue.formatted(.number.precision(.fractionLength(2))))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
                .accessibilityLabel(title)
        }
    }

    private func color(_ title: String, value: Binding<RecordingGlowColor>) -> some View {
        HStack {
            ColorPicker(title, selection: colorBinding(value), supportsOpacity: false)
                .accessibilityLabel(title)
                .accessibilityIdentifier(title)
            Text(value.wrappedValue.hex)
                .foregroundStyle(.secondary)
                .monospaced()
        }
    }

    private func colorBinding(_ value: Binding<RecordingGlowColor>) -> Binding<Color> {
        Binding(
            get: {
                let color = value.wrappedValue.normalized()
                return Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: 1)
            },
            set: { newValue in
                let uiColor = UIColor(newValue)
                var red: CGFloat = 0
                var green: CGFloat = 0
                var blue: CGFloat = 0
                var alpha: CGFloat = 0
                guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
                value.wrappedValue = RecordingGlowColor(
                    red: Double(red), green: Double(green), blue: Double(blue), opacity: 1
                )
            }
        )
    }

    private func reset() {
        preset = .figmaDefault
        response = .init()
        loudness = 0.52
        copied = false
    }

    private func copyJSON() {
        let snapshot = TuningSnapshot(preset: preset.normalized(), response: response)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot),
              let json = String(data: data, encoding: .utf8) else { return }
        UIPasteboard.general.string = json
        copied = true
    }
}

private struct TuningSnapshot: Codable {
    let preset: RecordingGlowPreset
    let response: LoudnessEnvelopeConfiguration
}
