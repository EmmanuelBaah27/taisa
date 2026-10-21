import Foundation

public struct RecordingGlowColor: Codable, Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    public init(hex: String, opacity: Double = 1) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(digits, radix: 16) ?? 0
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: opacity
        )
    }

    public var hex: String {
        let normalized = normalized()
        return String(
            format: "#%02X%02X%02X",
            Int((normalized.red * 255).rounded()),
            Int((normalized.green * 255).rounded()),
            Int((normalized.blue * 255).rounded())
        )
    }

    public func normalized() -> Self {
        .init(
            red: clamp(red),
            green: clamp(green),
            blue: clamp(blue),
            opacity: clamp(opacity)
        )
    }
}

public struct RecordingGlowRegion: Codable, Sendable, Equatable {
    public var color: RecordingGlowColor
    public var saturation: Double
    public var brightness: Double
    public var opacity: Double
    public var strength: Double

    public init(
        color: RecordingGlowColor,
        saturation: Double = 1,
        brightness: Double = 1,
        opacity: Double = 1,
        strength: Double
    ) {
        self.color = color
        self.saturation = saturation
        self.brightness = brightness
        self.opacity = opacity
        self.strength = strength
    }

    public func normalized() -> Self {
        .init(
            color: color.normalized(),
            saturation: clamp(saturation),
            brightness: clamp(brightness),
            opacity: clamp(opacity),
            strength: clamp(strength)
        )
    }
}

public struct RecordingGlowGrain: Codable, Sendable, Equatable {
    public var amount: Double
    public var scale: Double
    public var contrast: Double
    public var softness: Double
    public var loudnessInfluence: Double
    public var seed: UInt32

    public init(
        amount: Double,
        scale: Double,
        contrast: Double,
        softness: Double,
        loudnessInfluence: Double,
        seed: UInt32
    ) {
        self.amount = amount
        self.scale = scale
        self.contrast = contrast
        self.softness = softness
        self.loudnessInfluence = loudnessInfluence
        self.seed = seed
    }

    public func normalized() -> Self {
        .init(
            amount: clamp(amount),
            scale: max(clamp(scale), 0.001),
            contrast: clamp(contrast),
            softness: clamp(softness),
            loudnessInfluence: clamp(loudnessInfluence),
            seed: seed
        )
    }
}

public struct RecordingGlowPreset: Codable, Sendable, Equatable {
    public var leftOuter: RecordingGlowRegion
    public var leftInner: RecordingGlowRegion
    public var center: RecordingGlowRegion
    public var rightInner: RecordingGlowRegion
    public var rightOuter: RecordingGlowRegion

    public var centerBaselineHeight: Double
    public var centerPeakHeight: Double
    public var centerWidth: Double
    public var centerBloom: Double
    public var edgeGain: Double
    public var edgeSpread: Double
    public var edgeSoftness: Double
    public var edgeBalance: Double
    public var globalOpacity: Double
    public var verticalOrigin: Double
    public var grain: RecordingGlowGrain

    public var regions: [RecordingGlowRegion] {
        [leftOuter, leftInner, center, rightInner, rightOuter]
    }

    public init(
        leftOuter: RecordingGlowRegion,
        leftInner: RecordingGlowRegion,
        center: RecordingGlowRegion,
        rightInner: RecordingGlowRegion,
        rightOuter: RecordingGlowRegion,
        centerBaselineHeight: Double,
        centerPeakHeight: Double,
        centerWidth: Double,
        centerBloom: Double,
        edgeGain: Double,
        edgeSpread: Double,
        edgeSoftness: Double,
        edgeBalance: Double,
        globalOpacity: Double,
        verticalOrigin: Double,
        grain: RecordingGlowGrain
    ) {
        self.leftOuter = leftOuter
        self.leftInner = leftInner
        self.center = center
        self.rightInner = rightInner
        self.rightOuter = rightOuter
        self.centerBaselineHeight = centerBaselineHeight
        self.centerPeakHeight = centerPeakHeight
        self.centerWidth = centerWidth
        self.centerBloom = centerBloom
        self.edgeGain = edgeGain
        self.edgeSpread = edgeSpread
        self.edgeSoftness = edgeSoftness
        self.edgeBalance = edgeBalance
        self.globalOpacity = globalOpacity
        self.verticalOrigin = verticalOrigin
        self.grain = grain
    }

    public static let figmaDefault = RecordingGlowPreset(
        leftOuter: .init(color: .init(hex: "#F6B8B7"), saturation: 0.82, brightness: 0.96, opacity: 0.76, strength: 0.36),
        leftInner: .init(color: .init(hex: "#FDE68A"), saturation: 0.84, brightness: 0.95, opacity: 0.72, strength: 0.48),
        center: .init(color: .init(hex: "#CBAEFF"), saturation: 0.94, brightness: 1, opacity: 0.96, strength: 1),
        rightInner: .init(color: .init(hex: "#91C9FD"), saturation: 0.86, brightness: 0.98, opacity: 0.78, strength: 0.46),
        rightOuter: .init(color: .init(hex: "#ADEBB5"), saturation: 0.78, brightness: 0.94, opacity: 0.68, strength: 0.34),
        centerBaselineHeight: 0.12,
        centerPeakHeight: 0.72,
        centerWidth: 0.29,
        centerBloom: 0.58,
        edgeGain: 0.42,
        edgeSpread: 0.74,
        edgeSoftness: 0.62,
        edgeBalance: 0.5,
        globalOpacity: 0.92,
        verticalOrigin: 0.94,
        grain: .init(
            amount: 0.14,
            scale: 0.48,
            contrast: 0.42,
            softness: 0.64,
            loudnessInfluence: 0.22,
            seed: 0x5441_4953
        )
    )

    public func normalized() -> Self {
        .init(
            leftOuter: leftOuter.normalized(),
            leftInner: leftInner.normalized(),
            center: center.normalized(),
            rightInner: rightInner.normalized(),
            rightOuter: rightOuter.normalized(),
            centerBaselineHeight: clamp(centerBaselineHeight),
            centerPeakHeight: clamp(centerPeakHeight),
            centerWidth: clamp(centerWidth),
            centerBloom: clamp(centerBloom),
            edgeGain: clamp(edgeGain),
            edgeSpread: clamp(edgeSpread),
            edgeSoftness: clamp(edgeSoftness),
            edgeBalance: clamp(edgeBalance),
            globalOpacity: clamp(globalOpacity),
            verticalOrigin: clamp(verticalOrigin),
            grain: grain.normalized()
        )
    }
}

private func clamp(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), 1)
}
