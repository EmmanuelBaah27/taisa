import Testing
@testable import TaisaDesignSystem

@Suite("Recording reactive glow contract")
struct RecordingReactiveGlowContractTests {
    @Test("loudness is finite and clamped before uniforms are constructed")
    func loudnessIsClampedBeforeUniformConstruction() {
        #expect(RecordingGlowUniforms(loudness: -.infinity, state: .recording).loudness == 0)
        #expect(RecordingGlowUniforms(loudness: .nan, state: .recording).loudness == 0)
        #expect(RecordingGlowUniforms(loudness: 4, state: .recording).loudness == 1)
    }

    @Test("paused, unavailable, and Reduce Motion preserve static geometry")
    func pausedUnavailableAndReducedMotionUseStaticGeometry() {
        for state in [RecordingGlowState.paused, .reduceMotion, .unavailable] {
            let uniforms = RecordingGlowUniforms(loudness: 0.8, state: state)
            #expect(uniforms.spatialLoudness == 0)
            #expect(uniforms.usesStaticGeometry)
        }
        #expect(RecordingGlowUniforms(loudness: 0.8, state: .recording).spatialLoudness == 0.8)
    }

    @Test("grain coordinates are anchored to the preset seed, never loudness")
    func grainSeedDoesNotDependOnTimeOrLoudness() {
        let quiet = RecordingGlowUniforms(loudness: 0, state: .recording)
        let loud = RecordingGlowUniforms(loudness: 1, state: .recording)

        #expect(quiet.grainSeed == loud.grainSeed)
        #expect(quiet.grainSeed == RecordingGlowPreset.figmaDefault.grain.seed)
    }

    @Test("the purple center remains stronger than every supporting edge at peak")
    func centerContributionExceedsEveryEdgeAtPeak() {
        let uniforms = RecordingGlowUniforms(loudness: 1, state: .recording)

        #expect(uniforms.centerContribution > uniforms.leftOuterContribution)
        #expect(uniforms.centerContribution > uniforms.leftInnerContribution)
        #expect(uniforms.centerContribution > uniforms.rightInnerContribution)
        #expect(uniforms.centerContribution > uniforms.rightOuterContribution)
    }

    @Test("voice energy travels from the center through inner and outer colours")
    func waveTimingTravelsCenterOut() {
        let timing = RecordingGlowWaveTiming(staggerSeconds: 0.035)

        #expect(timing.centerDelay == 0)
        #expect(abs(timing.leftInnerDelay - 0.02625) < 0.000_001)
        #expect(timing.rightInnerDelay == 0.035)
        #expect(abs(timing.leftOuterDelay - 0.0525) < 0.000_001)
        #expect(timing.rightOuterDelay == 0.07)
    }

    @Test("invalid wave stagger values are bounded before animation")
    func waveTimingBoundsInvalidStagger() {
        #expect(RecordingGlowWaveTiming(staggerSeconds: -.infinity).outerDelay == 0)
        #expect(RecordingGlowWaveTiming(staggerSeconds: .nan).outerDelay == 0)
        #expect(RecordingGlowWaveTiming(staggerSeconds: 2).outerDelay == 0.36)
    }

    @Test("voice energy feels light and fluid rather than viscous")
    func waveMotionStaysLightAndFluid() {
        let motion = RecordingGlowWaveMotion.default

        #expect(motion.attackBounce > 0)
        #expect(motion.attackBounce == 0.45)
        #expect(motion.attackDuration == 0.16)
        #expect(motion.releaseDuration == 0.16)
    }
}
