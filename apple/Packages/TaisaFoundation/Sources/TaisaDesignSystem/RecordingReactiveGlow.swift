import SwiftUI

public enum RecordingGlowState: Sendable, Equatable {
    case recording
    case paused
    case reduceMotion
    case reducedTransparency
    case unavailable
}

public struct RecordingGlowFrequencyLevels: Sendable, Equatable {
    public let bass: Double
    public let lowMids: Double
    public let mids: Double
    public let upperMids: Double
    public let highs: Double

    public init(bass: Double, lowMids: Double, mids: Double, upperMids: Double, highs: Double) {
        self.bass = Self.clamp(bass)
        self.lowMids = Self.clamp(lowMids)
        self.mids = Self.clamp(mids)
        self.upperMids = Self.clamp(upperMids)
        self.highs = Self.clamp(highs)
    }

    public static let zero = Self(bass: 0, lowMids: 0, mids: 0, upperMids: 0, highs: 0)

    static func uniform(_ value: Double) -> Self {
        .init(bass: value, lowMids: value, mids: value, upperMids: value, highs: value)
    }

    func visualPresence(minimum: Double = 0.15) -> RecordingGlowWaveLevels {
        let floor = Self.clamp(minimum)
        let range = 1 - floor
        return .init(
            leftOuter: floor + bass * range,
            leftInner: floor + lowMids * range,
            center: floor + mids * range,
            rightInner: floor + upperMids * range,
            rightOuter: floor + highs * range
        )
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

struct RecordingGlowWaveTiming: Sendable, Equatable {
    let centerDelay: Double
    let leftInnerDelay: Double
    let rightInnerDelay: Double
    let leftOuterDelay: Double
    let rightOuterDelay: Double

    var outerDelay: Double { max(leftOuterDelay, rightOuterDelay) }

    init(staggerSeconds: Double) {
        let stagger = staggerSeconds.isFinite ? min(max(staggerSeconds, 0), 0.18) : 0
        centerDelay = 0
        leftInnerDelay = stagger * 0.75
        rightInnerDelay = stagger
        leftOuterDelay = stagger * 1.5
        rightOuterDelay = stagger * 2
    }
}

public struct RecordingGlowMotionConfiguration: Codable, Sendable, Equatable {
    public var waveStaggerSeconds: Double
    public var attackDuration: Double
    public var attackBounce: Double
    public var releaseDuration: Double

    public init(
        waveStaggerSeconds: Double,
        attackDuration: Double,
        attackBounce: Double,
        releaseDuration: Double
    ) {
        self.waveStaggerSeconds = waveStaggerSeconds
        self.attackDuration = attackDuration
        self.attackBounce = attackBounce
        self.releaseDuration = releaseDuration
    }

    public static let approved = Self(
        waveStaggerSeconds: 0.035,
        attackDuration: 0.16,
        attackBounce: 0.45,
        releaseDuration: 0.16
    )

    fileprivate var normalized: Self {
        .init(
            waveStaggerSeconds: clamped(waveStaggerSeconds, maximum: 0.18),
            attackDuration: clamped(attackDuration, minimum: 0.01, maximum: 2),
            attackBounce: clamped(attackBounce),
            releaseDuration: clamped(releaseDuration, minimum: 0.01, maximum: 2)
        )
    }
}

struct RecordingGlowWaveLevels: Sendable, Equatable {
    var leftOuter: Double
    var leftInner: Double
    var center: Double
    var rightInner: Double
    var rightOuter: Double

    static let zero = Self(leftOuter: 0, leftInner: 0, center: 0, rightInner: 0, rightOuter: 0)

    static func uniform(_ loudness: Double) -> Self {
        let value = loudness.isFinite ? min(max(loudness, 0), 1) : 0
        return Self(leftOuter: value, leftInner: value, center: value, rightInner: value, rightOuter: value)
    }
}

struct RecordingGlowUniforms: Sendable, Equatable {
    let loudness: Double
    let spatialLoudness: Double
    let usesStaticGeometry: Bool
    let preset: RecordingGlowPreset
    let waveLevels: RecordingGlowWaveLevels

    init(
        loudness: Double,
        state: RecordingGlowState,
        preset: RecordingGlowPreset = .figmaDefault,
        waveLevels: RecordingGlowWaveLevels? = nil
    ) {
        let safeLoudness = loudness.isFinite ? min(max(loudness, 0), 1) : 0
        let isStatic = state != .recording
        self.loudness = state == .paused || state == .unavailable ? 0 : safeLoudness
        let safeWaveLevels = waveLevels ?? .uniform(safeLoudness)
        self.waveLevels = isStatic ? .zero : safeWaveLevels
        spatialLoudness = isStatic ? 0 : safeWaveLevels.center
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
    private let loudness: Double
    private let state: RecordingGlowState
    private let preset: RecordingGlowPreset
    private let motion: RecordingGlowMotionConfiguration
    private let frequencyLevels: RecordingGlowFrequencyLevels
    @State private var waveLevels: RecordingGlowWaveLevels

    public init(
        loudness: Double,
        state: RecordingGlowState,
        preset: RecordingGlowPreset = .figmaDefault,
        motion: RecordingGlowMotionConfiguration = .approved,
        frequencyLevels: RecordingGlowFrequencyLevels? = nil
    ) {
        self.loudness = loudness
        self.state = state
        self.preset = preset
        self.motion = motion.normalized
        self.frequencyLevels = frequencyLevels ?? .uniform(loudness)
        let initialLevels = self.frequencyLevels.visualPresence()
        _waveLevels = State(initialValue: state == .recording ? initialLevels : .zero)
    }

    private var uniforms: RecordingGlowUniforms {
        RecordingGlowUniforms(loudness: loudness, state: state, preset: preset, waveLevels: waveLevels)
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
        .onChange(of: loudness) { _, _ in animateWave() }
        .onChange(of: frequencyLevels) { _, _ in animateWave() }
        .onChange(of: state) { _, _ in animateWave() }
    }

    private var shaderSurface: some View {
        let uniforms = uniforms
        return Rectangle()
            .fill(.white)
            .visualEffect { content, proxy in
                content.colorEffect(
                    ShaderLibrary.bundle(.module).recordingGlow(
                        .float2(proxy.size),
                        .float(Float(uniforms.loudness)),
                        .float(Float(uniforms.spatialLoudness)),
                        .float4(
                            Float(uniforms.waveLevels.leftOuter),
                            Float(uniforms.waveLevels.leftInner),
                            Float(uniforms.waveLevels.rightInner),
                            Float(uniforms.waveLevels.rightOuter)
                        ),
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

    private func animateWave() {
        let timing = RecordingGlowWaveTiming(staggerSeconds: motion.waveStaggerSeconds)
        let levels = state == .recording ? frequencyLevels.visualPresence() : .zero
        let isRising = max(levels.leftOuter, levels.leftInner, levels.center, levels.rightInner, levels.rightOuter)
            >= max(waveLevels.leftOuter, waveLevels.leftInner, waveLevels.center, waveLevels.rightInner, waveLevels.rightOuter)
        let animation = isRising
            ? Animation.spring(duration: motion.attackDuration, bounce: motion.attackBounce)
            : Animation.easeOut(duration: motion.releaseDuration)

        withAnimation(animation.delay(timing.centerDelay)) {
            waveLevels.center = levels.center
        }
        withAnimation(animation.delay(timing.leftInnerDelay)) {
            waveLevels.leftInner = levels.leftInner
        }
        withAnimation(animation.delay(timing.rightInnerDelay)) {
            waveLevels.rightInner = levels.rightInner
        }
        withAnimation(animation.delay(timing.leftOuterDelay)) {
            waveLevels.leftOuter = levels.leftOuter
        }
        withAnimation(animation.delay(timing.rightOuterDelay)) {
            waveLevels.rightOuter = levels.rightOuter
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

private func clamped(_ value: Double, minimum: Double = 0, maximum: Double = 1) -> Double {
    guard value.isFinite else { return minimum }
    return min(max(value, minimum), maximum)
}
