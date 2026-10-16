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
}
