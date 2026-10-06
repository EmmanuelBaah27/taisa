import CloudKit
import Foundation
import TaisaSync

/// Converts CloudKit failures to the transport-neutral, content-free taxonomy.
/// Never forwards CloudKit's localized description or userInfo to diagnostics.
public enum CloudKitErrorMapper {
    public static func map(_ error: Error, nowMS: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)) -> SyncTransportError {
        if error is CancellationError { return .retryable }
        guard let cloud = error as? CKError else { return .retryable }
        switch cloud.code {
        case .networkUnavailable, .networkFailure: return .offline
        case .quotaExceeded: return .quota
        case .notAuthenticated: return .accountChanged
        case .permissionFailure, .badContainer: return .permission
        case .changeTokenExpired: return .tokenExpired
        case .zoneNotFound, .userDeletedZone: return .zoneReset
        default:
            if let retry = cloud.retryAfterSeconds {
                return .rateLimited(retryAfterMS: deadline(after: retry, nowMS: nowMS))
            }
            if cloud.code == .requestRateLimited || cloud.code == .serviceUnavailable || cloud.code == .zoneBusy {
                return .rateLimited(retryAfterMS: deadline(after: 1, nowMS: nowMS))
            }
            return .retryable
        }
    }

    private static func deadline(after seconds: TimeInterval, nowMS: Int64) -> Int64 {
        let milliseconds = seconds.isFinite ? max(seconds * 1_000, 0) : 0
        let baseline = max(nowMS, 0)
        let remaining = Int64.max - baseline
        guard milliseconds < Double(remaining) else { return Int64.max }
        return baseline + Int64(milliseconds)
    }
}
