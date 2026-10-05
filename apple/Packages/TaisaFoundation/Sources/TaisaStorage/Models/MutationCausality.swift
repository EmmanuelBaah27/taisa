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

public struct CausalSnapshot: Codable, Sendable, Equatable {
    public let logicalVersionID: String
    public let recordParentVersionID: String?
    public let deviceID: String
    public let deviceCounter: Int64
    public let changedFields: [FieldCausalVersion]
    /// The local field frontier before this mutation, including a deletion.
    public let observedFieldVersions: [ObservedFieldVersion]
}
