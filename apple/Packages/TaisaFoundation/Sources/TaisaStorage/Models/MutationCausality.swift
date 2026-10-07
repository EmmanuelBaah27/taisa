/// Immutable causal information captured in the same transaction as a domain
/// mutation. IDs are opaque; timestamps never decide ancestry.
public struct FieldCausalVersion: Codable, Sendable, Equatable {
    public let fieldName: String
    public let versionID: String
    public let parentVersionID: String?
    /// Nearest ancestor first. The full path keeps a coalesced survivor
    /// intelligible even when intermediate unsent edits are suppressed.
    public let ancestorVersionIDs: [String]
    public let deviceCounter: Int64
}

public struct ObservedFieldVersion: Codable, Sendable, Equatable {
    public let fieldName: String
    public let versionID: String
}

public struct CausalDeviceCounter: Codable, Sendable, Equatable {
    public let deviceID: String
    public let counter: Int64

    public init(deviceID: String, counter: Int64) {
        self.deviceID = deviceID
        self.counter = counter
    }
}

/// Conservative evidence inherited by an explicit keep-deletion resolution.
public struct RetainedDeletionCausality: Codable, Sendable, Equatable {
    public let versionIDs: [String]
    public let latestDeletedAtMS: Int64
    public let frontier: [CausalDeviceCounter]
    public let observedFieldVersions: [ObservedFieldVersion]
    /// Field-tagged ancestry retained through compaction. Nil in legacy payloads.
    public let fieldAncestry: [String: [String]]?

    public init(versionIDs: [String], latestDeletedAtMS: Int64, frontier: [CausalDeviceCounter], observedFieldVersions: [ObservedFieldVersion], fieldAncestry: [String: [String]]? = nil) {
        self.versionIDs = versionIDs
        self.latestDeletedAtMS = latestDeletedAtMS
        self.frontier = frontier
        self.observedFieldVersions = observedFieldVersions
        self.fieldAncestry = fieldAncestry
    }
}

public struct CausalSnapshot: Codable, Sendable, Equatable {
    public let logicalVersionID: String
    public let recordParentVersionID: String?
    /// Additional parents of an explicit conflict resolution. Nil in legacy snapshots.
    public let resolvedParentVersionIDs: [String]?
    public let retainedDeletionCausality: RetainedDeletionCausality?
    public let deviceID: String
    public let deviceCounter: Int64
    public let changedFields: [FieldCausalVersion]
    /// The local field frontier before this mutation, including a deletion.
    public let observedFieldVersions: [ObservedFieldVersion]

    public init(logicalVersionID: String, recordParentVersionID: String?, resolvedParentVersionIDs: [String]? = nil, retainedDeletionCausality: RetainedDeletionCausality? = nil, deviceID: String, deviceCounter: Int64, changedFields: [FieldCausalVersion], observedFieldVersions: [ObservedFieldVersion]) {
        self.logicalVersionID = logicalVersionID
        self.recordParentVersionID = recordParentVersionID
        self.resolvedParentVersionIDs = resolvedParentVersionIDs
        self.retainedDeletionCausality = retainedDeletionCausality
        self.deviceID = deviceID
        self.deviceCounter = deviceCounter
        self.changedFields = changedFields
        self.observedFieldVersions = observedFieldVersions
    }
}
