import Foundation
import Testing
@testable import TaisaSecurity

@Suite struct VaultTests {
    @Test func recoveryKeyRoundTripsAndRejectsDamage() throws {
        let key = try RecoveryKey.generate()
        let text = key.formatted
        #expect(text.hasPrefix("TAISA1-"))
        #expect(try RecoveryKey(validating: text.lowercased()).formatted == text)
        #expect(throws: VaultError.invalidRecoveryKey) {
            try RecoveryKey(validating: String(text.dropLast()) + (text.last == "0" ? "1" : "0"))
        }
        #expect(throws: VaultError.invalidRecoveryKey) {
            try RecoveryKey(validating: text.replacingOccurrences(of: "-", with: ""))
        }
    }

    @Test func recoveryKeyFixedVector() throws {
        let bytes = Data(repeating: 0, count: 32)
        let key = try RecoveryKey(keyMaterial: bytes)
        #expect(key.formatted == "TAISA1-00000000-00000000-00000000-00000000-00000000-00000000-00000000-00000000-7083596B")
    }

    @Test func unwrapsFixedHKDFAndAESGCMVector() throws {
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let combined = "33333333333333333333333300596A02AF7A2131F7D375471FBB6C2094A4808DE17BB949F179992B8C22270D5230DD3FC1243078C5A8741481BF0ACB"
        let bytes = stride(from: 0, to: combined.count, by: 2).map { offset -> UInt8 in
            let start = combined.index(combined.startIndex, offsetBy: offset)
            return UInt8(combined[start..<combined.index(start, offsetBy: 2)], radix: 16)!
        }
        let wrapper = WrappedVaultKey(version: 1, vaultID: id,
                                      salt: Data(repeating: 0x22, count: 32), ciphertext: Data(bytes))
        let recovery = try RecoveryKey(keyMaterial: Data(repeating: 0, count: 32))
        let vault = try Vault.unwrap(wrapper, using: recovery)
        #expect(vault.id == id)
        #expect(throws: VaultError.wrongRecoveryKey) {
            try Vault.unwrap(wrapper, using: RecoveryKey.generate())
        }
    }

    @Test func vaultSealsWithUniqueNoncesAndAuthenticatedMetadata() throws {
        let vault = try Vault.generate()
        let metadata = EnvelopeMetadata(vaultID: vault.id, recordID: UUID(), entityType: "message", schemaVersion: 1, tombstone: false)
        let plaintext = Data("PRIVATE-CANARY".utf8)
        let first = try vault.seal(plaintext, metadata: metadata)
        let second = try vault.seal(plaintext, metadata: metadata)
        #expect(first.ciphertext != second.ciphertext)
        #expect(first.ciphertext.prefix(12) != second.ciphertext.prefix(12))
        #expect(try vault.open(first) == plaintext)
        #expect(!first.ciphertext.contains(plaintext))
        var changed = first
        changed.metadata.tombstone = true
        #expect(throws: VaultError.authenticationFailed) { try vault.open(changed) }
        changed = first
        changed.ciphertext[changed.ciphertext.startIndex] ^= 1
        #expect(throws: VaultError.authenticationFailed) { try vault.open(changed) }
        changed = first
        changed.metadata.recordID = UUID()
        #expect(throws: VaultError.authenticationFailed) { try vault.open(changed) }
        changed = first
        changed.metadata.entityType = "goal"
        #expect(throws: VaultError.authenticationFailed) { try vault.open(changed) }
        changed = first
        changed.metadata.schemaVersion = 2
        #expect(throws: VaultError.authenticationFailed) { try vault.open(changed) }
        changed = first
        changed.metadata.vaultID = UUID()
        #expect(throws: VaultError.authenticationFailed) { try vault.open(changed) }
        #expect(throws: VaultError.authenticationFailed) { try Vault.generate().open(first) }
    }

    @Test func malformedAndUnsupportedEnvelopesFailClosed() throws {
        let vault = try Vault.generate()
        let metadata = EnvelopeMetadata(vaultID: vault.id, recordID: UUID(), entityType: "goal", schemaVersion: 1, tombstone: false)
        var envelope = try vault.seal(Data("private".utf8), metadata: metadata)
        envelope.version = 2
        #expect(throws: VaultError.unsupportedVersion) { try vault.open(envelope) }
        envelope.version = 1
        envelope.ciphertext = Data(repeating: 0, count: 3)
        #expect(throws: VaultError.malformedEnvelope) { try vault.open(envelope) }
    }

    @Test func privateContentCannotBecomeCleartextEntityType() throws {
        let vault = try Vault.generate()
        let metadata = EnvelopeMetadata(vaultID: vault.id, recordID: UUID(),
                                        entityType: "privatecareerstory", schemaVersion: 1, tombstone: false)
        #expect(throws: VaultError.malformedEnvelope) {
            try vault.seal(Data("private".utf8), metadata: metadata)
        }
    }

    @Test func wrappingAndRotationKeepVaultIdentityAndRejectOldKey() throws {
        let vault = try Vault.generate()
        let metadata = EnvelopeMetadata(vaultID: vault.id, recordID: UUID(), entityType: "message", schemaVersion: 1, tombstone: false)
        let sealed = try vault.seal(Data("kept after rotation".utf8), metadata: metadata)
        let oldKey = try RecoveryKey.generate()
        let wrapped = try vault.wrap(using: oldKey)
        #expect(try Vault.unwrap(wrapped, using: oldKey).id == vault.id)
        #expect(throws: VaultError.wrongRecoveryKey) { try Vault.unwrap(wrapped, using: RecoveryKey.generate()) }
        let rotated = try vault.rotateRecoveryKey(current: oldKey, wrapped: wrapped)
        let reopened = try Vault.unwrap(rotated.wrappedVault, using: rotated.recoveryKey)
        #expect(reopened.id == vault.id)
        #expect(try reopened.open(sealed) == Data("kept after rotation".utf8))
        #expect(throws: VaultError.wrongRecoveryKey) { try Vault.unwrap(rotated.wrappedVault, using: oldKey) }
        var tampered = rotated.wrappedVault
        tampered.vaultID = UUID()
        #expect(throws: VaultError.wrongRecoveryKey) { try Vault.unwrap(tampered, using: rotated.recoveryKey) }
        tampered = rotated.wrappedVault
        tampered.version = 2
        #expect(throws: VaultError.unsupportedVersion) { try Vault.unwrap(tampered, using: rotated.recoveryKey) }
        tampered = rotated.wrappedVault
        tampered.salt = Data(repeating: 0, count: 1)
        #expect(throws: VaultError.malformedEnvelope) { try Vault.unwrap(tampered, using: rotated.recoveryKey) }
        tampered = rotated.wrappedVault
        tampered.ciphertext = Data(repeating: 0, count: 3)
        #expect(throws: VaultError.malformedEnvelope) { try Vault.unwrap(tampered, using: rotated.recoveryKey) }
    }

    @Test func errorsAndDebugOutputNeverRevealKeyMaterial() throws {
        let key = try RecoveryKey.generate()
        let vault = try Vault.generate()
        let wrapped = try vault.wrap(using: key)
        let wrong = try RecoveryKey.generate()
        do { _ = try Vault.unwrap(wrapped, using: wrong) } catch {
            #expect(!String(describing: error).contains(key.formatted))
            #expect(!String(describing: error).contains(wrong.formatted))
        }
        #expect(!String(reflecting: vault).contains(key.formatted))
    }
}
