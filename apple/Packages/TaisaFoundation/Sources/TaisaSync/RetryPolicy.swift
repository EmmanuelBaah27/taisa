import Foundation

public enum RetryPolicy {
    public static func nextAttemptMS(nowMS: Int64, attempts: Int, retryAfterMS: Int64? = nil) -> Int64 {
        let shift = min(max(attempts, 0), 8)
        let delay = min(Int64(1_000) << shift, 300_000)
        let exponential = nowMS.addingReportingOverflow(delay)
        let calculated = exponential.overflow ? Int64.max : exponential.partialValue
        return max(calculated, retryAfterMS ?? 0)
    }
}
