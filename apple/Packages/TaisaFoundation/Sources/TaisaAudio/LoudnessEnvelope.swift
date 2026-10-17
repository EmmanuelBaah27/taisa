import Foundation

public struct LoudnessEnvelopeConfiguration: Codable, Sendable, Equatable {
    public var noiseFloorDecibels: Double
    public var ceilingDecibels: Double
    public var inputGain: Double
    public var responseExponent: Double
    public var peakContribution: Double
    public var attackSeconds: Double
    public var releaseSeconds: Double
    public var maximumRisePerSecond: Double

    public init(
        noiseFloorDecibels: Double = -55,
        ceilingDecibels: Double = -6,
        inputGain: Double = 1,
        responseExponent: Double = 0.75,
        peakContribution: Double = 0.2,
        attackSeconds: Double = 0.07,
        releaseSeconds: Double = 0.28,
        maximumRisePerSecond: Double = 7
    ) {
        self.noiseFloorDecibels = noiseFloorDecibels
        self.ceilingDecibels = ceilingDecibels
        self.inputGain = inputGain
        self.responseExponent = responseExponent
        self.peakContribution = peakContribution
        self.attackSeconds = attackSeconds
        self.releaseSeconds = releaseSeconds
        self.maximumRisePerSecond = maximumRisePerSecond
    }
}

public struct LoudnessEnvelope: Sendable {
    public private(set) var value: Double
    public let configuration: LoudnessEnvelopeConfiguration

    public init(
        configuration: LoudnessEnvelopeConfiguration = .init(),
        initialValue: Double = 0
    ) {
        self.configuration = configuration
        value = Self.clamp(initialValue)
    }

    @discardableResult
    public mutating func update(sample: AudioMeterSample, delta: Duration) -> Double {
        let elapsed = max(delta.seconds, 0)
        guard elapsed > 0 else { return value }

        let average = normalized(decibels: Double(sample.averagePower))
        let peak = normalized(decibels: Double(sample.peakPower))
        let peakWeight = Self.clamp(configuration.peakContribution)
        let target = Self.clamp(
            ((average * (1 - peakWeight)) + (peak * peakWeight))
                * max(configuration.inputGain, 0)
        )

        let timeConstant = target > value
            ? configuration.attackSeconds
            : configuration.releaseSeconds
        let alpha = 1 - exp(-elapsed / max(timeConstant, 0.001))
        var next = value + ((target - value) * alpha)

        if next > value {
            let maximumRise = max(configuration.maximumRisePerSecond, 0) * elapsed
            next = min(next, value + maximumRise)
        }

        value = Self.clamp(next)
        return value
    }

    @discardableResult
    public mutating func reset() -> Double {
        value = 0
        return value
    }

    private func normalized(decibels: Double) -> Double {
        let floor = configuration.noiseFloorDecibels
        let ceiling = max(configuration.ceilingDecibels, floor + 0.001)
        guard decibels.isFinite, floor.isFinite, ceiling.isFinite else { return 0 }
        guard decibels > floor else { return 0 }

        let linear = Self.clamp((decibels - floor) / (ceiling - floor))
        return pow(linear, max(configuration.responseExponent, 0.001))
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

private extension Duration {
    var seconds: Double {
        let parts = components
        return Double(parts.seconds) + (Double(parts.attoseconds) / 1e18)
    }
}
