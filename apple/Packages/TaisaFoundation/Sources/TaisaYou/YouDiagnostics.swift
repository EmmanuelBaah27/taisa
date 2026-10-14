import TaisaStorage

public enum YouDiagnosticID: String, Sendable, CaseIterable, Hashable {
    case localStore
    case recovery
    case microphone
    case voiceGateway
    case appProtection
}

public struct YouDiagnosticRow: Sendable, Equatable, Identifiable {
    public let id: YouDiagnosticID
    public let label: String
    public let value: String

    public init(id: YouDiagnosticID, label: String, value: String) {
        self.id = id
        self.label = label
        self.value = value
    }
}

public enum YouDiagnostics {
    public static func rows(for facts: YouOperationalFacts) -> [YouDiagnosticRow] {
        [
            .init(id: .localStore, label: "Local store", value: facts.store.displayName),
            .init(id: .recovery, label: "Recovery", value: facts.recovery.displayName),
            .init(id: .microphone, label: "Microphone", value: facts.microphone.displayName),
            .init(id: .voiceGateway, label: "Voice gateway", value: facts.gateway.displayName),
            .init(id: .appProtection, label: "App protection", value: facts.appProtection.displayName),
        ]
    }
}

private extension YouHealth {
    var displayName: String { rawValue.capitalized }
}

private extension YouRecoveryStatus {
    var displayName: String {
        switch self {
        case .ready: "Ready"
        case .setupRequired: "Setup required"
        case .recoveryRequired: "Recovery required"
        case .unknown: "Unknown"
        }
    }
}

private extension YouPermissionStatus {
    var displayName: String {
        switch self {
        case .granted: "Allowed"
        case .denied: "Not allowed"
        case .restricted: "Restricted"
        case .notDetermined: "Not requested"
        }
    }
}

private extension YouProtectionStatus {
    var displayName: String { rawValue.capitalized }
}
