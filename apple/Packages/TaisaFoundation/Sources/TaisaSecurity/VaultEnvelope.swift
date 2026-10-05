import Foundation

/// All fields are authenticated. IDs must be opaque transport identifiers, never user content.
public struct EnvelopeMetadata: Codable, Equatable, Sendable {
    private static let allowedEntityTypes: Set<String> = [
        "profile", "conversation", "message", "goal", "milestone", "action",
        "evidence", "memory", "memory_source", "snapshot",
    ]
    public var vaultID: UUID
    public var recordID: UUID
    public var entityType: String
    public var schemaVersion: Int
    public var tombstone: Bool

    public init(vaultID: UUID, recordID: UUID, entityType: String, schemaVersion: Int, tombstone: Bool) {
        self.vaultID = vaultID
        self.recordID = recordID
        self.entityType = entityType
        self.schemaVersion = schemaVersion
        self.tombstone = tombstone
    }

    func validate() throws {
        guard Self.allowedEntityTypes.contains(entityType),
              schemaVersion > 0
        else { throw VaultError.malformedEnvelope }
    }
}

public struct VaultEnvelope: Codable, Equatable, Sendable {
    public var version: Int
    public var metadata: EnvelopeMetadata
    /// CryptoKit AES.GCM combined representation: 12-byte nonce, ciphertext, 16-byte tag.
    public var ciphertext: Data

    public init(version: Int, metadata: EnvelopeMetadata, ciphertext: Data) {
        self.version = version
        self.metadata = metadata
        self.ciphertext = ciphertext
    }
}

public struct WrappedVaultKey: Codable, Equatable, Sendable {
    public var version: Int
    public var vaultID: UUID
    public var salt: Data
    public var ciphertext: Data

    public init(version: Int, vaultID: UUID, salt: Data, ciphertext: Data) {
        self.version = version
        self.vaultID = vaultID
        self.salt = salt
        self.ciphertext = ciphertext
    }
}
