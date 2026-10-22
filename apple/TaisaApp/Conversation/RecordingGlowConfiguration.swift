import Foundation
import TaisaAudio
import TaisaDesignSystem

struct RecordingGlowConfiguration: Codable, Equatable, Sendable {
    let schemaVersion: Int
    var preset: RecordingGlowPreset
    var response: LoudnessEnvelopeConfiguration
    var motion: RecordingGlowMotionConfiguration
    var surfaceHeight: Double

    init(
        schemaVersion: Int = 1,
        preset: RecordingGlowPreset,
        response: LoudnessEnvelopeConfiguration,
        motion: RecordingGlowMotionConfiguration,
        surfaceHeight: Double
    ) {
        self.schemaVersion = schemaVersion
        self.preset = preset
        self.response = response
        self.motion = motion
        self.surfaceHeight = surfaceHeight
    }

    static let approved = Self(
        preset: .figmaDefault,
        response: .recordingGlowApproved,
        motion: .approved,
        surfaceHeight: Double(TaisaControlMetric.recordingGlowSurfaceHeight)
    )
}
