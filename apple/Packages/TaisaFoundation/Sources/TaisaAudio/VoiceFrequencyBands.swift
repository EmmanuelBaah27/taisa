import Foundation

public struct VoiceFrequencyBands: Sendable, Equatable, Codable {
    public var bass: Double
    public var lowMids: Double
    public var mids: Double
    public var upperMids: Double
    public var highs: Double

    public init(
        bass: Double,
        lowMids: Double,
        mids: Double,
        upperMids: Double,
        highs: Double
    ) {
        self.bass = Self.clamp(bass)
        self.lowMids = Self.clamp(lowMids)
        self.mids = Self.clamp(mids)
        self.upperMids = Self.clamp(upperMids)
        self.highs = Self.clamp(highs)
    }

    public static let zero = Self(bass: 0, lowMids: 0, mids: 0, upperMids: 0, highs: 0)

    public var values: [Double] { [bass, lowMids, mids, upperMids, highs] }

    init(values: [Double]) {
        self.init(
            bass: values[safe: 0] ?? 0,
            lowMids: values[safe: 1] ?? 0,
            mids: values[safe: 2] ?? 0,
            upperMids: values[safe: 3] ?? 0,
            highs: values[safe: 4] ?? 0
        )
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
