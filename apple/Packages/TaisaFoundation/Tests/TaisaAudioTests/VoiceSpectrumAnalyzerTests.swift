import Foundation
import Testing
@testable import TaisaAudio

@Suite("Voice frequency spectrum analyzer")
struct VoiceSpectrumAnalyzerTests {
    // Breaks first: wrong band edges, sample-rate-dependent mapping, rumble leakage,
    // non-finite input, and an envelope that either flickers or hangs after speech.

    @Test("each reference tone predominantly activates its ordered voice band", arguments: [44_100.0, 48_000.0])
    func referenceTonesMapLeftToRight(sampleRate: Double) {
        let cases: [(frequency: Double, keyPath: KeyPath<VoiceFrequencyBands, Double>)] = [
            (120, \VoiceFrequencyBands.bass),
            (250, \VoiceFrequencyBands.lowMids),
            (700, \VoiceFrequencyBands.mids),
            (2_000, \VoiceFrequencyBands.upperMids),
            (5_000, \VoiceFrequencyBands.highs),
        ]

        for testCase in cases {
            var analyzer = VoiceSpectrumAnalyzer()
            let bands = analyzer.analyze(
                samples: sineWave(frequency: testCase.frequency, sampleRate: sampleRate),
                sampleRate: sampleRate,
                delta: .milliseconds(23)
            )
            let expected = bands[keyPath: testCase.keyPath]
            let others = bands.values.filter { $0 != expected }

            #expect(expected > 0.55)
            #expect(expected > (others.max() ?? 0) * 1.6)
        }
    }

    @Test("silence, sub-voice rumble, and unusable buffers stay flat")
    func rejectsNonVoiceAndInvalidInput() {
        var analyzer = VoiceSpectrumAnalyzer()

        #expect(analyzer.analyze(samples: [], sampleRate: 48_000, delta: .milliseconds(20)) == .zero)
        #expect(analyzer.analyze(samples: [0, 0, 0], sampleRate: 48_000, delta: .milliseconds(20)) == .zero)
        #expect(analyzer.analyze(samples: sineWave(frequency: 40, sampleRate: 48_000), sampleRate: 48_000, delta: .milliseconds(20)) == .zero)
        #expect(analyzer.analyze(samples: [.nan, .infinity, -.infinity], sampleRate: 48_000, delta: .milliseconds(20)) == .zero)
        #expect(analyzer.analyze(samples: Array(repeating: 0, count: 2_048), sampleRate: .nan, delta: .milliseconds(20)) == .zero)
    }

    @Test("five values are always finite and clamped")
    func outputIsFiniteAndClamped() {
        var analyzer = VoiceSpectrumAnalyzer()
        let bands = analyzer.analyze(
            samples: sineWave(frequency: 700, sampleRate: 48_000, amplitude: 8),
            sampleRate: 48_000,
            delta: .seconds(4)
        )

        #expect(bands.values.allSatisfy { $0.isFinite && (0...1).contains($0) })
    }

    @Test("attack is immediate while release remains light and finite")
    func smoothingRespondsThenSettles() {
        var analyzer = VoiceSpectrumAnalyzer()
        let tone = sineWave(frequency: 700, sampleRate: 48_000)

        let first = analyzer.analyze(samples: tone, sampleRate: 48_000, delta: .milliseconds(20))
        let second = analyzer.analyze(samples: tone, sampleRate: 48_000, delta: .milliseconds(20))
        let released = analyzer.analyze(
            samples: Array(repeating: 0, count: 2_048),
            sampleRate: 48_000,
            delta: .milliseconds(20)
        )

        #expect(first.mids > 0)
        #expect(second.mids >= first.mids)
        #expect(released.mids < second.mids)
        #expect(released.mids > 0)
    }

    private func sineWave(
        frequency: Double,
        sampleRate: Double,
        amplitude: Double = 0.8,
        count: Int = 2_048
    ) -> [Float] {
        (0..<count).map { index in
            Float(amplitude * sin(2 * .pi * frequency * Double(index) / sampleRate))
        }
    }
}
