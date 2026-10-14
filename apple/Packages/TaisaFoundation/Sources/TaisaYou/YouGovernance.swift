import TaisaStorage

public struct CapabilityChangeReview: Sendable, Equatable {
    public let id: CapabilityID
    public let from: CapabilityGovernanceState
    public let to: CapabilityGovernanceState

    public init(id: CapabilityID, from: CapabilityGovernanceState, to: CapabilityGovernanceState) {
        self.id = id
        self.from = from
        self.to = to
    }
}

public enum YouPrivacyCopy {
    public static let readableData = "Career profile and capability choices"
    public static let encryptedLocation = "Encrypted on this device"
    public static let microphonePurpose = "Microphone access is requested only when you start recording."
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
