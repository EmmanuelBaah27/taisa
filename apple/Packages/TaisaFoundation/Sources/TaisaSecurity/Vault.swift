import CryptoKit
import Foundation

public struct Vault: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let id: UUID
    private let keyMaterial: Data
    private static let version = 1
    private static let wrapContext = Data("taisa.vault-wrap.v1".utf8)

    public static func generate() throws -> Vault {
        try Vault(id: UUID(), keyMaterial: SecurityRandom.bytes(count: 32))
    }

    init(id: UUID, keyMaterial: Data) throws {
        guard keyMaterial.count == 32 else { throw VaultError.invalidKeyLength }
        self.id = id
        self.keyMaterial = keyMaterial
    }

    public func seal(_ plaintext: Data, metadata: EnvelopeMetadata) throws -> VaultEnvelope {
        try metadata.validate()
        guard metadata.vaultID == id else { throw VaultError.authenticationFailed }
        let aad = try Self.associatedData(version: Self.version, metadata: metadata)
        let box = try AES.GCM.seal(plaintext, using: SymmetricKey(data: keyMaterial), authenticating: aad)
        guard let combined = box.combined else { throw VaultError.malformedEnvelope }
        return VaultEnvelope(version: Self.version, metadata: metadata, ciphertext: combined)
    }

    public func open(_ envelope: VaultEnvelope) throws -> Data {
        guard envelope.version == Self.version else { throw VaultError.unsupportedVersion }
        try envelope.metadata.validate()
        guard envelope.metadata.vaultID == id else { throw VaultError.authenticationFailed }
        guard envelope.ciphertext.count >= 28 else { throw VaultError.malformedEnvelope }
        let aad = try Self.associatedData(version: envelope.version, metadata: envelope.metadata)
        do {
            let box = try AES.GCM.SealedBox(combined: envelope.ciphertext)
            return try AES.GCM.open(box, using: SymmetricKey(data: keyMaterial), authenticating: aad)
        } catch { throw VaultError.authenticationFailed }
    }

    public func wrap(using recoveryKey: RecoveryKey) throws -> WrappedVaultKey {
        let salt = try SecurityRandom.bytes(count: 32)
        let derived = Self.deriveWrappingKey(from: recoveryKey, salt: salt)
        let aad = Self.wrapAssociatedData(vaultID: id, version: Self.version)
        let box = try AES.GCM.seal(keyMaterial, using: derived, authenticating: aad)
        guard let combined = box.combined else { throw VaultError.malformedEnvelope }
        return WrappedVaultKey(version: Self.version, vaultID: id, salt: salt, ciphertext: combined)
    }

    public static func unwrap(_ wrapped: WrappedVaultKey, using recoveryKey: RecoveryKey) throws -> Vault {
        guard wrapped.version == version else { throw VaultError.unsupportedVersion }
        guard wrapped.salt.count == 32, wrapped.ciphertext.count >= 60 else { throw VaultError.malformedEnvelope }
        let derived = deriveWrappingKey(from: recoveryKey, salt: wrapped.salt)
        let aad = wrapAssociatedData(vaultID: wrapped.vaultID, version: wrapped.version)
        do {
            let box = try AES.GCM.SealedBox(combined: wrapped.ciphertext)
            let material = try AES.GCM.open(box, using: derived, authenticating: aad)
            return try Vault(id: wrapped.vaultID, keyMaterial: material)
        } catch { throw VaultError.wrongRecoveryKey }
    }

    /// Produces the replacement wrapper. The caller must atomically replace the active wrapper;
    /// retained copies of the previous wrapper and key cannot be cryptographically revoked.
    public func rotateRecoveryKey(current: RecoveryKey, wrapped: WrappedVaultKey) throws -> RecoveryRotation {
        let opened = try Self.unwrap(wrapped, using: current)
        guard opened.id == id, Self.constantTimeEqual(opened.keyMaterial, keyMaterial) else {
            throw VaultError.authenticationFailed
        }
        let replacement = try RecoveryKey.generate()
        return RecoveryRotation(recoveryKey: replacement, wrappedVault: try wrap(using: replacement))
    }

    private static func associatedData(version: Int, metadata: EnvelopeMetadata) throws -> Data {
        struct Binding: Encodable {
            let version: Int
            let vaultID: UUID
            let recordID: UUID
            let entityType: String
            let schemaVersion: Int
            let tombstone: Bool
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Binding(version: version, vaultID: metadata.vaultID,
                                          recordID: metadata.recordID, entityType: metadata.entityType,
                                          schemaVersion: metadata.schemaVersion, tombstone: metadata.tombstone))
    }

    private static func wrapAssociatedData(vaultID: UUID, version: Int) -> Data {
        Data("taisa.vault-key.v1|\(version)|\(vaultID.uuidString)".utf8)
    }

    private static func deriveWrappingKey(from key: RecoveryKey, salt: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: key.keyMaterial), salt: salt,
                               info: wrapContext, outputByteCount: 32)
    }

    private static func constantTimeEqual(_ left: Data, _ right: Data) -> Bool {
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices { difference |= left[index] ^ right[index] }
        return difference == 0
    }

    public var description: String { "<redacted vault \(id.uuidString)>" }
    public var debugDescription: String { description }
}

public struct RecoveryRotation: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let recoveryKey: RecoveryKey
    public let wrappedVault: WrappedVaultKey
    public var description: String { "<redacted recovery rotation>" }
    public var debugDescription: String { description }
}
