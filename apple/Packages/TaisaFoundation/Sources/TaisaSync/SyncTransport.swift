import Foundation
import TaisaSecurity

public enum SyncAccountState: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    case available(fingerprint: Data)
    case offline
    case noAccount
    case unavailable

    public var description: String { "<sync account state>" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["state": "redacted"], displayStyle: .enum) }
}

/// These errors carry only a category and optional scheduling metadata.
public enum SyncTransportError: Error, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    case offline
    case quota
    case rateLimited(retryAfterMS: Int64)
    case retryable
    case permission
    case tokenExpired
    case zoneReset
    case accountChanged

    public var description: String {
        switch self {
        case .offline: "Sync offline"
        case .quota: "Sync storage full"
        case .rateLimited: "Sync rate limited"
        case .retryable: "Sync temporarily unavailable"
        case .permission: "Sync permission denied"
        case .tokenExpired: "Sync token expired"
        case .zoneReset: "Sync zone reset"
        case .accountChanged: "Sync account changed"
        }
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["category": description], displayStyle: .enum) }
}

public struct EncryptedChange: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let id: String
    public let envelope: VaultEnvelope

    public init(id: String, envelope: VaultEnvelope) {
        self.id = id
        self.envelope = envelope
    }

    public var description: String { "<redacted encrypted change>" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["state": "redacted"], displayStyle: .struct) }
}

public struct SyncFetchPage: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let changes: [EncryptedChange]
    public let token: Data?
    public let hasMore: Bool

    public init(changes: [EncryptedChange], token: Data?, hasMore: Bool = false) {
        self.changes = changes
        self.token = token
        self.hasMore = hasMore
    }

    public var description: String { "<redacted sync page>" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["state": "redacted"], displayStyle: .struct) }
}

public struct SyncSendResult: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let acknowledgedIDs: [String]
    public let failures: [String: SyncTransportError]

    public init(acknowledgedIDs: [String], failures: [String: SyncTransportError] = [:]) {
        self.acknowledgedIDs = acknowledgedIDs
        self.failures = failures
    }

    public var description: String { "<redacted sync send result>" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["state": "redacted"], displayStyle: .struct) }
}

public protocol SyncTransport: Sendable {
    func accountState() async -> SyncAccountState
    func fetch(after token: Data?) async throws -> SyncFetchPage
    func send(_ changes: [EncryptedChange]) async throws -> SyncSendResult
}
