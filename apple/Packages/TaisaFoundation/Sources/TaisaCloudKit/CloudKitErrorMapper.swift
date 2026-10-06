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
        case .requestRateLimited, .serviceUnavailable:
            let seconds = max(cloud.retryAfterSeconds ?? 1, 0)
            let delay = min(seconds * 1_000, Double(Int64.max / 2))
            return .rateLimited(retryAfterMS: nowMS + Int64(delay))
        default: return .retryable
        }
    }
}
