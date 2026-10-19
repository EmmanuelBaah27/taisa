import TaisaStorage

public struct ResponsePreferenceSignal: Sendable, Equatable {
    public let factor: ResponseQualityFactor
    public let direction: ResponseFeedbackDirection
}

public enum ResponsePreferenceProfile {
    public static func derive(from recent: [ResponseFeedbackRecord]) -> [ResponsePreferenceSignal] {
        let bounded = Array(recent.prefix(10))
        var counts: [ResponseQualityFactor: [ResponseFeedbackDirection: Int]] = [:]
        for feedback in bounded {
            for factor in feedback.factors where factor != .evidenceFidelity {
                counts[factor, default: [:]][feedback.direction, default: 0] += 1
            }
        }
        return counts.compactMap { factor, directions in
            let helpful = directions[.helpful, default: 0]
            let notHelpful = directions[.notHelpful, default: 0]
            guard helpful != notHelpful, max(helpful, notHelpful) >= 2 else { return nil }
            return ResponsePreferenceSignal(factor: factor, direction: helpful > notHelpful ? .helpful : .notHelpful)
        }
        .sorted { $0.factor.rawValue < $1.factor.rawValue }
        .prefix(5)
        .map { $0 }
    }
}
