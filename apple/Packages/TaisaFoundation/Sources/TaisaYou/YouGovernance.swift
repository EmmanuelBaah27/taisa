import TaisaStorage

public enum YouPrivacyCopy {
    public static let readableData = "Career profile"
    public static let encryptedLocation = "Encrypted on this device"
    public static let microphonePurpose = "Microphone access is requested only when you start recording."
    public static let networkBoundary = "Only a deliberate voice or coaching action sends the bounded request to the configured provider. Browsing You stays offline."
    public static let retentionBoundary = "Your readable career profile remains in encrypted local storage until you edit it or restore a verified backup."
    public static let recoveryBoundary = "A backup can replace local data only after authentication, integrity checks, explicit confirmation, and post-restore verification."
}

public struct YouPermissionGuidance: Sendable, Equatable {
    public let status: YouPermissionStatus
    public let requestsPermission: Bool
    public let guidance: String

    public static func microphone(_ status: YouPermissionStatus) -> Self {
        let guidance = switch status {
        case .granted: "Available when you choose to record."
        case .denied: "Microphone access is off. You can change it in Settings before recording."
        case .restricted: "Microphone access is restricted on this device."
        case .notDetermined: YouPrivacyCopy.microphonePurpose
        }
        return .init(status: status, requestsPermission: false, guidance: guidance)
    }
}
