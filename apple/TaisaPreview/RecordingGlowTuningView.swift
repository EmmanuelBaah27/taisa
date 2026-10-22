@preconcurrency import AVFoundation
import SwiftUI
import TaisaAudio
import TaisaDesignSystem
import UIKit

struct RecordingGlowTuningView: View {
    @StateObject private var liveMeter = PreviewLiveLoudnessMonitor()
    @State private var preset = RecordingGlowPreset.figmaDefault
    @State private var response = LoudnessEnvelopeConfiguration.recordingGlowApproved
    @State private var loudness = 0.52
    @State private var simulatedBands = VoiceFrequencyBands(
        bass: 0.42,
        lowMids: 0.58,
        mids: 0.72,
        upperMids: 0.46,
        highs: 0.28
    )
    @State private var inputMode = TuningInputMode.simulated
    @State private var simulatedState = SimulatedGlowState.recording
    @State private var waveStagger = 0.035
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            RecordingReactiveGlow(
                loudness: displayedLoudness,
                state: simulatedState.recordingGlowState,
                preset: preset,
                waveStagger: waveStagger,
                frequencyLevels: displayedFrequencyLevels
            )
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .padding(.horizontal, TaisaSpacing.page.rawValue)
                .padding(.vertical, TaisaSpacing.standard.rawValue)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "Recording glow preview, loudness \(displayedLoudness.formatted(.percent.precision(.fractionLength(0))))"
                )
                .accessibilityIdentifier("recording-glow.surface")

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: TaisaSpacing.section.rawValue) {
                    section("Input source") {
                        choiceGrid(TuningInputMode.allCases, selection: $inputMode)
                        if inputMode == .simulated {
                            slider("Simulated loudness", value: $loudness)
                            frequencySliders
                        } else {
                            liveLevel
                        }
                    }

                    section("Visual state") {
                        choiceGrid(SimulatedGlowState.allCases, selection: $simulatedState)
                    }

                    section("Response") {
                        slider("Input gain", value: $response.inputGain, range: 0...2)
                        slider("Response curve", value: $response.responseExponent, range: 0.2...2)
                        slider("Attack seconds", value: $response.attackSeconds, range: 0.02...0.6)
                        slider("Release seconds", value: $response.releaseSeconds, range: 0.1...1.5)
                        slider("Wave stagger seconds", value: $waveStagger, range: 0...0.18)
                    }

                    section("Center") {
                        slider("Center baseline height", value: $preset.centerBaselineHeight)
                        slider("Center peak height", value: $preset.centerPeakHeight)
                        slider("Center width", value: $preset.centerWidth)
                        slider("Center bloom", value: $preset.centerBloom)
                    }

                    section("Supporting edges") {
                        slider("Edge gain", value: $preset.edgeGain)
                        slider("Edge spread", value: $preset.edgeSpread)
                        slider("Edge softness", value: $preset.edgeSoftness)
                        slider("Edge balance", value: $preset.edgeBalance)
                    }

                    section("Palette · bass coral") {
                        region("Bass coral", value: $preset.leftOuter)
                    }
                    section("Palette · low-mid yellow") {
                        region("Low-mid yellow", value: $preset.leftInner)
                    }
                    section("Palette · mid purple") {
                        region("Mid purple", value: $preset.center)
                    }
                    section("Palette · upper-mid blue") {
                        region("Upper-mid blue", value: $preset.rightInner)
                    }
                    section("Palette · right outer green") {
                        region("Right outer green", value: $preset.rightOuter)
                    }

                    section("Grain and composition") {
                        slider("Grain intensity", value: $preset.grain.amount)
                        slider("Grain size", value: $preset.grain.scale)
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
            .accessibilityIdentifier("recording-glow.controls")
        }
        .task(id: inputMode) {
            if inputMode == .liveMicrophone {
                await liveMeter.start(configuration: response)
            } else {
                liveMeter.stop()
            }
        }
        .onChange(of: response) { _, updated in
            liveMeter.update(configuration: updated)
        }
        .onDisappear { liveMeter.stop() }
    }

    private var displayedLoudness: Double {
        inputMode == .simulated ? loudness : liveMeter.loudness
    }

    private var displayedFrequencyLevels: RecordingGlowFrequencyLevels {
        let bands = inputMode == .simulated ? simulatedBands : liveMeter.frequencyBands
        return .init(
            bass: bands.bass,
            lowMids: bands.lowMids,
            mids: bands.mids,
            upperMids: bands.upperMids,
            highs: bands.highs
        )
    }

    private var frequencySliders: some View {
        VStack(alignment: .leading, spacing: TaisaSpacing.standard.rawValue) {
            Text("Frequency energy").font(.subheadline.weight(.semibold))
            slider("Bass · coral", value: $simulatedBands.bass)
            slider("Low-mids · yellow", value: $simulatedBands.lowMids)
            slider("Mids · purple", value: $simulatedBands.mids)
            slider("Upper-mids · blue", value: $simulatedBands.upperMids)
            slider("Highs · green", value: $simulatedBands.highs)
        }
    }

    private var liveLevel: some View {
        VStack(alignment: .leading, spacing: TaisaSpacing.compact.rawValue) {
            HStack {
                Text("Live level")
                Spacer()
                Text(displayedLoudness.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit()
            }
            ProgressView(value: displayedLoudness)
            ForEach(Array(zip(frequencyLabels, liveMeter.frequencyBands.values)), id: \.0) { label, value in
                HStack(spacing: 8) {
                    Text(label).frame(width: 88, alignment: .leading)
                    ProgressView(value: value)
                    Text(value.formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
                .font(.caption)
            }
            Text(liveMeter.status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live microphone level")
        .accessibilityValue(displayedLoudness.formatted(.percent.precision(.fractionLength(0))))
    }

    private var frequencyLabels: [String] {
        ["Bass", "Low-mids", "Mids", "Upper-mids", "Highs"]
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

    private func choiceGrid<Choice: TuningChoice>(
        _ choices: [Choice],
        selection: Binding<Choice>
    ) -> some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                if index.isMultiple(of: 2) {
                    GridRow {
                        choiceButton(choice, selection: selection)
                        if index + 1 < choices.count {
                            choiceButton(choices[index + 1], selection: selection)
                        } else {
                            Color.clear
                        }
                    }
                }
            }
        }
    }

    private func choiceButton<Choice: TuningChoice>(
        _ choice: Choice,
        selection: Binding<Choice>
    ) -> some View {
        Button {
            selection.wrappedValue = choice
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selection.wrappedValue == choice ? "checkmark.circle.fill" : "circle")
                Text(choice.title)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .accessibilityAddTraits(selection.wrappedValue == choice ? .isSelected : [])
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

    @ViewBuilder
    private func region(_ title: String, value: Binding<RecordingGlowRegion>) -> some View {
        color("\(title) color", value: value.color)
        slider("\(title) saturation", value: value.saturation)
        slider("\(title) brightness", value: value.brightness)
        slider("\(title) opacity", value: value.opacity)
        slider("\(title) strength", value: value.strength)
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
        response = .recordingGlowApproved
        loudness = 0.52
        simulatedBands = .init(bass: 0.42, lowMids: 0.58, mids: 0.72, upperMids: 0.46, highs: 0.28)
        inputMode = .simulated
        simulatedState = .recording
        waveStagger = 0.035
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

private protocol TuningChoice: Hashable, Identifiable {
    var title: String { get }
}

private enum TuningInputMode: String, CaseIterable, TuningChoice {
    case simulated
    case liveMicrophone

    var id: String { rawValue }
    var title: String { self == .simulated ? "Simulated" : "Live microphone" }
}

private enum SimulatedGlowState: String, CaseIterable, TuningChoice {
    case recording
    case paused
    case reduceMotion
    case reducedTransparency

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recording: "Recording"
        case .paused: "Paused"
        case .reduceMotion: "Reduce motion"
        case .reducedTransparency: "Less transparency"
        }
    }

    var recordingGlowState: RecordingGlowState {
        switch self {
        case .recording: .recording
        case .paused: .paused
        case .reduceMotion: .reduceMotion
        case .reducedTransparency: .reducedTransparency
        }
    }
}

@MainActor
private final class PreviewLiveLoudnessMonitor: ObservableObject {
    @Published private(set) var loudness = 0.0
    @Published private(set) var frequencyBands = VoiceFrequencyBands.zero
    @Published private(set) var status = "Microphone off"

    private let engine = AVAudioEngine()
    private var envelope = LoudnessEnvelope()
    private var spectrumAnalyzer = VoiceSpectrumAnalyzer()
    private var tapInstalled = false

    func start(configuration: LoudnessEnvelopeConfiguration) async {
        stop()
        status = "Requesting microphone access…"
        guard await AVAudioApplication.requestRecordPermission() else {
            status = "Microphone access denied"
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
            try session.setActive(true)

            envelope = LoudnessEnvelope(configuration: configuration)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                status = "Microphone unavailable"
                return
            }

            let sampleRate = format.sampleRate
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { @Sendable [weak self] buffer, _ in
                guard let reading = Self.meterReading(from: buffer, sampleRate: sampleRate) else {
                    return
                }
                Task { @MainActor [weak self] in
                    self?.consume(
                        reading.sample,
                        samples: reading.samples,
                        sampleRate: sampleRate,
                        delta: reading.delta
                    )
                }
            }
            tapInstalled = true
            engine.prepare()
            try engine.start()
            status = "Listening — speak to test the glow"
        } catch {
            stop()
            status = "Couldn’t start microphone"
        }
    }

    func update(configuration: LoudnessEnvelopeConfiguration) {
        envelope = LoudnessEnvelope(configuration: configuration, initialValue: loudness)
    }

    func stop() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        loudness = 0
        frequencyBands = .zero
        spectrumAnalyzer.reset()
        status = "Microphone off"
    }

    private func consume(
        _ sample: AudioMeterSample,
        samples: [Float],
        sampleRate: Double,
        delta: Duration
    ) {
        loudness = envelope.update(sample: sample, delta: delta)
        frequencyBands = spectrumAnalyzer.analyze(samples: samples, sampleRate: sampleRate, delta: delta)
        status = "Listening — receiving audio"
    }

    private nonisolated static func meterReading(
        from buffer: AVAudioPCMBuffer,
        sampleRate: Double
    ) -> (sample: AudioMeterSample, samples: [Float], delta: Duration)? {
        guard let channel = buffer.floatChannelData?.pointee else { return nil }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return nil }

        var sumSquares: Float = 0
        var peak: Float = 0
        for index in 0..<count {
            let sample = abs(channel[index])
            sumSquares += sample * sample
            peak = max(peak, sample)
        }

        let average = sqrt(sumSquares / Float(count))
        let averageDB = 20 * log10(max(average, 0.000_000_1))
        let peakDB = 20 * log10(max(peak, 0.000_000_1))
        return (
            AudioMeterSample(averagePower: averageDB, peakPower: peakDB),
            Array(UnsafeBufferPointer(start: channel, count: count)),
            .seconds(Double(count) / sampleRate)
        )
    }
}

private struct TuningSnapshot: Codable {
    let preset: RecordingGlowPreset
    let response: LoudnessEnvelopeConfiguration
}
