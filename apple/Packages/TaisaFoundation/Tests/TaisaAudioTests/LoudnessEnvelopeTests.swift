import Foundation
import Testing
@testable import TaisaAudio

@Suite("Loudness presentation envelope")
struct LoudnessEnvelopeTests {
    private let frame = Duration.milliseconds(100)

    @Test("silence and sub-threshold room noise stay flat")
    func silenceAndSubthresholdNoiseStayAtZero() {
        var envelope = LoudnessEnvelope()

        for sample in [
            AudioMeterSample(averagePower: -160, peakPower: -160),
            AudioMeterSample(averagePower: -64, peakPower: -58),
        ] {
            #expect(envelope.update(sample: sample, delta: frame) == 0)
        }
    }

    @Test("conversational speech rises responsively without jumping to peak")
    func conversationalSpeechRisesWithoutJumpingToPeak() {
        var envelope = LoudnessEnvelope()

        let first = envelope.update(
            sample: .init(averagePower: -24, peakPower: -12),
            delta: frame
        )
        let sustained = (0..<5).reduce(first) { _, _ in
            envelope.update(sample: .init(averagePower: -24, peakPower: -12), delta: frame)
        }

        #expect(first > 0)
        #expect(first < sustained)
        #expect(sustained < 1)
    }

    @Test("attack is faster than release for the same elapsed time")
    func attackIsFasterThanReleaseForEqualDelta() {
        var rising = LoudnessEnvelope()
        let attackMovement = rising.update(
            sample: .init(averagePower: -16, peakPower: -8),
            delta: frame
        )

        var falling = LoudnessEnvelope(initialValue: 1)
        let released = falling.update(
            sample: .init(averagePower: -160, peakPower: -160),
            delta: frame
        )
        let releaseMovement = 1 - released

        #expect(attackMovement > releaseMovement)
        #expect(released > 0)
    }

    @Test("a single peak is softened while sustained loudness reaches a bounded maximum")
    func singlePeakSampleIsSuppressedButSustainedPeakReachesBoundedMaximum() {
        var envelope = LoudnessEnvelope()
        let sample = AudioMeterSample(averagePower: 0, peakPower: 0)

        let transient = envelope.update(sample: sample, delta: frame)
        var sustained = transient
        for _ in 0..<40 {
            sustained = envelope.update(sample: sample, delta: frame)
        }

        #expect(transient > 0)
        #expect(transient < 0.75)
        #expect(sustained > 0.9)
        #expect(sustained <= 1)
    }

    @Test("non-finite and out-of-range input always returns a finite clamped value")
    func nonFiniteAndOutOfRangeSamplesReturnFiniteClampedOutput() {
        var envelope = LoudnessEnvelope()
        let samples = [
            AudioMeterSample(averagePower: .nan, peakPower: .infinity),
            AudioMeterSample(averagePower: -.infinity, peakPower: 500),
            AudioMeterSample(averagePower: 500, peakPower: 500),
        ]

        for sample in samples {
            let value = envelope.update(sample: sample, delta: .milliseconds(100))
            #expect(value.isFinite)
            #expect((0...1).contains(value))
        }
    }

    @Test("reset returns immediately to the flat state")
    func resetReturnsImmediatelyToZero() {
        var envelope = LoudnessEnvelope(initialValue: 1)

        #expect(envelope.reset() == 0)
        #expect(envelope.value == 0)
    }
}
