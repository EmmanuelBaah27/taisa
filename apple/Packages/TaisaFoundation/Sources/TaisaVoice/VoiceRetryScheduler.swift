import Foundation

public struct VoiceRetryScheduler: Sendable {
    private let baseDelay: TimeInterval
    private let maximumDelay: TimeInterval
    private let maximumAttempts: Int
    private let jitter: @Sendable (Int) -> TimeInterval

    public init(
        baseDelay: TimeInterval = 1,
        maximumDelay: TimeInterval = 30,
        maximumAttempts: Int = 4,
        jitter: @escaping @Sendable (Int) -> TimeInterval = { _ in 0 }
    ) {
        self.baseDelay = max(0, baseDelay)
        self.maximumDelay = max(0, maximumDelay)
        self.maximumAttempts = max(0, maximumAttempts)
        self.jitter = jitter
    }

    public func delay(forAttempt attempt: Int) -> TimeInterval? {
        guard attempt >= 0, attempt < maximumAttempts else { return nil }
        let multiplier = pow(2, Double(min(attempt, 62)))
        let backoff = min(maximumDelay, baseDelay * multiplier)
        return min(maximumDelay, max(0, backoff + jitter(attempt)))
    }
}

public protocol VoiceRetrySleeping: Sendable {
    func sleep(for seconds: TimeInterval) async throws
}

public struct SystemVoiceRetrySleeper: VoiceRetrySleeping {
    public init() {}

    public func sleep(for seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(max(0, seconds)))
    }
}
