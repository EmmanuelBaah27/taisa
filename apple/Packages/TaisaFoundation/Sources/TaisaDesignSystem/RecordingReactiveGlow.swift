import SwiftUI

public enum RecordingGlowState: Sendable, Equatable {
    case recording
    case paused
    case reduceMotion
    case reducedTransparency
    case unavailable
}

struct RecordingGlowUniforms: Sendable, Equatable {
    let loudness: Double
    let spatialLoudness: Double
    let usesStaticGeometry: Bool
    let preset: RecordingGlowPreset

    init(
        loudness: Double,
        state: RecordingGlowState,
        preset: RecordingGlowPreset = .figmaDefault
    ) {
        let safeLoudness = loudness.isFinite ? min(max(loudness, 0), 1) : 0
        let isStatic = state != .recording
        self.loudness = state == .paused || state == .unavailable ? 0 : safeLoudness
        spatialLoudness = isStatic ? 0 : safeLoudness
        usesStaticGeometry = isStatic
        self.preset = preset.normalized()
    }

    var grainSeed: UInt32 { preset.grain.seed }
    var centerContribution: Double { preset.center.strength }
    var leftOuterContribution: Double { preset.leftOuter.strength * preset.edgeGain }
    var leftInnerContribution: Double { preset.leftInner.strength * preset.edgeGain }
    var rightInnerContribution: Double { preset.rightInner.strength * preset.edgeGain }
    var rightOuterContribution: Double { preset.rightOuter.strength * preset.edgeGain }
}

public struct RecordingReactiveGlow: View {
    private let uniforms: RecordingGlowUniforms
    private let state: RecordingGlowState

    public init(
        loudness: Double,
        state: RecordingGlowState,
        preset: RecordingGlowPreset = .figmaDefault
    ) {
        self.state = state
        uniforms = RecordingGlowUniforms(loudness: loudness, state: state, preset: preset)
    }

    public var body: some View {
        Group {
            switch state {
            case .unavailable, .reducedTransparency:
                staticFallback
            case .recording, .paused, .reduceMotion:
                shaderSurface
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var shaderSurface: some View {
        Rectangle()
            .fill(.white)
            .visualEffect { content, proxy in
                content.colorEffect(
                    ShaderLibrary.bundle(.module).recordingGlow(
                        .float2(proxy.size),
                        .float(Float(uniforms.loudness)),
                        .float(Float(uniforms.spatialLoudness)),
                        .color(uniforms.preset.leftOuter.color.swiftUIColor),
                        .color(uniforms.preset.leftInner.color.swiftUIColor),
                        .color(uniforms.preset.center.color.swiftUIColor),
                        .color(uniforms.preset.rightInner.color.swiftUIColor),
                        .color(uniforms.preset.rightOuter.color.swiftUIColor),
                        .float(Float(uniforms.leftOuterContribution)),
                        .float(Float(uniforms.leftInnerContribution)),
                        .float(Float(uniforms.centerContribution)),
                        .float(Float(uniforms.rightInnerContribution)),
                        .float(Float(uniforms.rightOuterContribution)),
                        .float4(
                            Float(uniforms.preset.centerBaselineHeight),
                            Float(uniforms.preset.centerPeakHeight),
                            Float(uniforms.preset.centerWidth),
                            Float(uniforms.preset.centerBloom)
                        ),
                        .float4(
                            Float(uniforms.preset.edgeSpread),
                            Float(uniforms.preset.edgeSoftness),
                            Float(uniforms.preset.edgeBalance),
                            Float(uniforms.preset.verticalOrigin)
                        ),
                        .float4(
                            Float(uniforms.preset.grain.amount),
                            Float(uniforms.preset.grain.scale),
                            Float(uniforms.preset.grain.contrast),
                            Float(uniforms.preset.grain.softness)
                        ),
                        .float(Float(uniforms.preset.grain.loudnessInfluence)),
                        .float(Float(uniforms.grainSeed)),
                        .float(Float(uniforms.preset.globalOpacity))
                    )
                )
            }
    }

    private var staticFallback: some View {
        LinearGradient(
            colors: uniforms.preset.regions.map { region in
                region.color.swiftUIColor.opacity(region.opacity * region.strength)
            },
            startPoint: .leading,
            endPoint: .trailing
        )
        .mask(
            LinearGradient(
                colors: [.clear, .black.opacity(0.16), .black],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .opacity(uniforms.preset.globalOpacity * 0.68)
    }
}

private extension RecordingGlowColor {
    var swiftUIColor: Color {
        let color = normalized()
        return Color(
            .sRGB,
            red: color.red,
            green: color.green,
            blue: color.blue,
            opacity: color.opacity
        )
    }
}
