import Foundation
import Testing
@testable import TaisaDesignSystem

@Suite("Recording glow preset")
struct RecordingGlowPresetTests {
    @Test("the default preserves the approved Figma palette and center hierarchy")
    func figmaDefaultUsesApprovedFiveColorOrder() {
        let preset = RecordingGlowPreset.figmaDefault

        #expect(preset.regions.map(\.color.hex) == [
            "#F6B8B7", "#FDE68A", "#CBAEFF", "#91C9FD", "#ADEBB5",
        ])
        #expect(preset.center.strength > preset.leftOuter.strength)
        #expect(preset.center.strength > preset.leftInner.strength)
        #expect(preset.center.strength > preset.rightInner.strength)
        #expect(preset.center.strength > preset.rightOuter.strength)
    }

    @Test("normalization clamps opacity, contribution, geometry, and grain")
    func normalizationClampsOpacityGainGeometryAndGrain() {
        var preset = RecordingGlowPreset.figmaDefault
        preset.globalOpacity = 3
        preset.verticalOrigin = -2
        preset.center.strength = -1
        preset.centerBaselineHeight = -4
        preset.centerPeakHeight = 7
        preset.centerWidth = 5
        preset.edgeGain = 4
        preset.grain.amount = 2
        preset.grain.scale = -8
        preset.grain.contrast = 6
        preset.grain.softness = -1
        preset.grain.loudnessInfluence = 3

        let normalized = preset.normalized()

        #expect(normalized.globalOpacity == 1)
        #expect(normalized.verticalOrigin == 0)
        #expect(normalized.center.strength == 0)
        #expect(normalized.centerBaselineHeight == 0)
        #expect(normalized.centerPeakHeight == 1)
        #expect(normalized.centerWidth == 1)
        #expect(normalized.edgeGain == 1)
        #expect(normalized.grain.amount == 1)
        #expect(normalized.grain.scale == 0.001)
        #expect(normalized.grain.contrast == 1)
        #expect(normalized.grain.softness == 0)
        #expect(normalized.grain.loudnessInfluence == 1)
    }

    @Test("encoding round-trip preserves every tunable field")
    func encodingRoundTripPreservesEveryTunableField() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(RecordingGlowPreset.figmaDefault)
        let decoded = try JSONDecoder().decode(RecordingGlowPreset.self, from: data)

        #expect(decoded == .figmaDefault)
        #expect(String(decoding: data, as: UTF8.self).hasPrefix("{"))
    }

    @Test("the anchored procedural grain seed survives export")
    func fixedGrainSeedSurvivesExport() throws {
        let data = try JSONEncoder().encode(RecordingGlowPreset.figmaDefault)
        let decoded = try JSONDecoder().decode(RecordingGlowPreset.self, from: data)

        #expect(decoded.grain.seed == RecordingGlowPreset.figmaDefault.grain.seed)
        #expect(decoded.grain.seed == 0x5441_4953)
    }

    @Test("the preset has no timer or autonomous motion parameter")
    func presetContainsNoTimerOrAutonomousMotionParameter() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(
            decoding: try encoder.encode(RecordingGlowPreset.figmaDefault),
            as: UTF8.self
        ).lowercased()

        #expect(!json.contains("time"))
        #expect(!json.contains("phase"))
        #expect(!json.contains("speed"))
    }
}
