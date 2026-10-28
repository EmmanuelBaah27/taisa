import Accelerate
import Foundation

public struct VoiceSpectrumConfiguration: Sendable, Equatable {
    public var bandRanges: [ClosedRange<Double>]
    public var noiseFloorRMS: Double
    public var attackSeconds: Double
    public var releaseSeconds: Double

    public init(
        bandRanges: [ClosedRange<Double>] = [80...180, 180...350, 350...1_200, 1_200...3_000, 3_000...8_000],
        noiseFloorRMS: Double = 0.004,
        attackSeconds: Double = 0.012,
        releaseSeconds: Double = 0.14
    ) {
        self.bandRanges = bandRanges
        self.noiseFloorRMS = noiseFloorRMS
        self.attackSeconds = attackSeconds
        self.releaseSeconds = releaseSeconds
    }
}

public struct VoiceSpectrumAnalyzer {
    public let configuration: VoiceSpectrumConfiguration
    public private(set) var value: VoiceFrequencyBands

    public init(
        configuration: VoiceSpectrumConfiguration = .init(),
        initialValue: VoiceFrequencyBands = .zero
    ) {
        self.configuration = configuration
        value = initialValue
    }

    public mutating func analyze(
        samples: [Float],
        sampleRate: Double,
        delta: Duration
    ) -> VoiceFrequencyBands {
        guard sampleRate.isFinite,
              sampleRate > 0,
              samples.count >= 64,
              configuration.bandRanges.count == 5
        else {
            value = .zero
            return value
        }

        let count = 1 << Int(floor(log2(Double(samples.count))))
        let input = samples.suffix(count).map { $0.isFinite ? $0 : 0 }
        let rms = sqrt(input.reduce(0) { $0 + Double($1 * $1) } / Double(count))
        let raw: [Double]

        if rms < configuration.noiseFloorRMS {
            raw = Array(repeating: 0, count: 5)
        } else {
            raw = spectrumLevels(input: input, sampleRate: sampleRate)
        }

        let elapsed = max(delta.secondsValue, 0)
        let previous = value.values
        let smoothed = zip(previous, raw).map { old, target in
            let timeConstant = target >= old ? configuration.attackSeconds : configuration.releaseSeconds
            guard timeConstant.isFinite, timeConstant > 0, elapsed.isFinite else { return target }
            let blend = 1 - exp(-elapsed / timeConstant)
            return old + ((target - old) * blend)
        }
        value = VoiceFrequencyBands(values: smoothed)
        return value
    }

    @discardableResult
    public mutating func reset() -> VoiceFrequencyBands {
        value = .zero
        return value
    }

    private func spectrumLevels(input: [Float], sampleRate: Double) -> [Double] {
        let count = input.count
        guard let transform = try? vDSP.DiscreteFourierTransform(
            previous: nil,
            count: count,
            direction: .forward,
            transformType: .complexComplex,
            ofType: Float.self
        ) else {
            return Array(repeating: 0, count: 5)
        }

        let window = vDSP.window(
            ofType: Float.self,
            usingSequence: .hanningDenormalized,
            count: count,
            isHalfWindow: false
        )
        let windowed = vDSP.multiply(input, window)
        let inputImaginary = Array(repeating: Float.zero, count: count)
        var real = Array(repeating: Float.zero, count: count)
        var imaginary = Array(repeating: Float.zero, count: count)
        transform.transform(
            inputReal: windowed,
            inputImaginary: inputImaginary,
            outputReal: &real,
            outputImaginary: &imaginary
        )

        let binWidth = sampleRate / Double(count)
        let dominantBin = (1..<(real.count / 2)).max { lhs, rhs in
            let left = (real[lhs] * real[lhs]) + (imaginary[lhs] * imaginary[lhs])
            let right = (real[rhs] * real[rhs]) + (imaginary[rhs] * imaginary[rhs])
            return left < right
        }
        guard let dominantBin, Double(dominantBin) * binWidth >= 70 else {
            return Array(repeating: 0, count: 5)
        }

        var energies = Array(repeating: 0.0, count: 5)
        for bin in 1..<(real.count / 2) {
            let frequency = Double(bin) * binWidth
            guard let band = configuration.bandRanges.firstIndex(where: { $0.contains(frequency) }) else { continue }
            let magnitudeSquared = Double((real[bin] * real[bin]) + (imaginary[bin] * imaginary[bin]))
            energies[band] += magnitudeSquared
        }

        let amplitudes = energies.map(sqrt)
        guard let peak = amplitudes.max(), peak.isFinite, peak > 0 else {
            return Array(repeating: 0, count: 5)
        }
        return amplitudes.map { min(max($0 / peak, 0), 1) }
    }
}

private extension Duration {
    var secondsValue: Double {
        let parts = components
        return Double(parts.seconds) + (Double(parts.attoseconds) / 1e18)
    }
}
