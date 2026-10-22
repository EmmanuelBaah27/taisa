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

    static let approved: Self = {
        do {
            return try loadApproved(from: .main)
        } catch {
            preconditionFailure("Missing or invalid bundled recording glow configuration: \(error)")
        }
    }()

    static func loadApproved(from bundle: Bundle) throws -> Self {
        guard let url = bundle.url(forResource: "voice-recorder-shader", withExtension: "json") else {
            throw RecordingGlowConfigurationError.missingResource
        }
        let configuration = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard configuration.schemaVersion == 1 else {
            throw RecordingGlowConfigurationError.unsupportedSchema(configuration.schemaVersion)
        }
        guard configuration.surfaceHeight.isFinite, configuration.surfaceHeight > 0 else {
            throw RecordingGlowConfigurationError.invalidSurfaceHeight
        }
        return configuration
    }
}

private enum RecordingGlowConfigurationError: Error {
    case missingResource
    case unsupportedSchema(Int)
    case invalidSurfaceHeight
}
