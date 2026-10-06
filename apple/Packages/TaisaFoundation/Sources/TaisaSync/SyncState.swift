import Foundation

public enum SyncReason: Sendable { case localChange, notification, foreground, manual }

public enum SyncState: String, Codable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case idle
    case syncing
    case upToDate
    case offline
    case noAccount
    case unavailable
    case accountChanged
    case storageFull
    case retrying
    case recoveryRequired
    case zoneReset
    case conflictsNeedReview

    public var description: String {
        switch self {
        case .idle: "Sync idle"
        case .syncing: "Syncing"
        case .upToDate: "Up to date"
        case .offline: "Offline; changes saved locally"
        case .noAccount: "iCloud account required"
        case .unavailable: "iCloud unavailable"
        case .accountChanged: "iCloud account changed"
        case .storageFull: "iCloud storage full"
        case .retrying: "Sync will retry"
        case .recoveryRequired: "Sync needs recovery"
        case .zoneReset: "Sync zone needs recovery"
        case .conflictsNeedReview: "Conflicts need review"
        }
    }

    public var debugDescription: String { description }
}

public struct SyncOutcome: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let state: SyncState
    public let uploaded: Int
    public let downloaded: Int
    public let conflicts: Int
    public let quarantined: Int
    public let retryAtMS: Int64?

    public init(state: SyncState, uploaded: Int = 0, downloaded: Int = 0,
                conflicts: Int = 0, quarantined: Int = 0, retryAtMS: Int64? = nil) {
        self.state = state
        self.uploaded = uploaded
        self.downloaded = downloaded
        self.conflicts = conflicts
        self.quarantined = quarantined
        self.retryAtMS = retryAtMS
    }

    public var description: String { "<sync outcome>" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["state": "redacted"], displayStyle: .struct) }
}
