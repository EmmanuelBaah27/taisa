public enum SyncCapability: Equatable, Sendable {
    case localOnly
    case fakePreview
    case privateCloudKit

    public static func forEnvironment(_ environment: TaisaEnvironment) -> Self {
        switch environment {
        case .personal: .localOnly
        case .preview: .fakePreview
        case .development, .production: .privateCloudKit
        }
    }
}
