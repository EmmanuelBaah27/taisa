public enum YouDestination: String, Sendable, CaseIterable, Hashable {
    case careerProfile
    case privacyPermissions
    case backupRecovery
    case diagnostics

    public var stableID: String { rawValue }
    public var title: String {
        switch self {
        case .careerProfile: "Career profile"
        case .privacyPermissions: "Privacy & permissions"
        case .backupRecovery: "Backup & recovery"
        case .diagnostics: "Diagnostics"
        }
    }
    public var systemImage: String {
        switch self {
        case .careerProfile: "person.text.rectangle"
        case .privacyPermissions: "hand.raised"
        case .backupRecovery: "arrow.clockwise.icloud"
        case .diagnostics: "stethoscope"
        }
    }
}
