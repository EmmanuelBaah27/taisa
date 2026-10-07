import Foundation
import Testing
import TaisaStorage
import TaisaVoice
@testable import TaisaSecurity

@Suite struct DiagnosticRedactionTests {
    @Test func directAndNestedDiagnosticsCannotRevealRawKeys() throws {
        let recovery = try RecoveryKey(keyMaterial: Data(repeating: 0xAB, count: 32))
        let vault = try Vault(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
                              keyMaterial: Data(repeating: 0xCD, count: 32))
        let wrapped = WrappedVaultKey(version: 1, vaultID: vault.id,
                                      salt: Data(repeating: 0xAB, count: 32),
                                      ciphertext: Data(repeating: 0xCD, count: 60))
        let rotation = RecoveryRotation(recoveryKey: recovery, wrappedVault: wrapped)
        let setup = RecoverySetupState(recoveryKey: recovery)
        let objects: [Any] = [recovery, vault, setup, rotation, wrapped,
                              [recovery], ["vault": vault], [setup], [rotation]]
        let forbidden = [recovery.formatted, String(repeating: "AB", count: 32),
                         String(repeating: "CD", count: 32),
                         Data(repeating: 0xAB, count: 32).base64EncodedString(),
                         Data(repeating: 0xCD, count: 32).base64EncodedString(),
                         "keyMaterial", "recoveryKey", "ciphertext", "salt", "171", "205"]
        for object in objects {
            let output = diagnosticText(object)
            for secret in forbidden { #expect(!output.contains(secret)) }
        }
        #expect(!JSONSerialization.isValidJSONObject([recovery]))
        #expect(!JSONSerialization.isValidJSONObject([vault]))
        #expect(!JSONSerialization.isValidJSONObject([setup]))
        #expect(!JSONSerialization.isValidJSONObject([rotation]))
        for secret: Any in [recovery, vault, setup, rotation] {
            #expect(!(secret is any Encodable))
        }
    }

    @Test func envelopeDiagnosticsRedactEvenCiphertextAndOpaqueMetadata() throws {
        let metadata = EnvelopeMetadata(
            vaultID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            recordID: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
            entityType: "message", schemaVersion: 1, tombstone: false)
        let envelope = VaultEnvelope(version: 1, metadata: metadata,
                                     ciphertext: Data(repeating: 0xEF, count: 60))
        let output = diagnosticText([envelope, metadata])
        for forbidden in ["ciphertext", "metadata:", "recordID", "vaultID", "239",
                          String(repeating: "EF", count: 60),
                          envelope.ciphertext.base64EncodedString()] {
            #expect(!output.contains(forbidden))
        }
        #expect(output.contains("redacted"))
    }

    @Test func voiceDiagnosticsNeverRevealConversationContentOrAudioIdentity() {
        let forbidden = [
            "private-transcript", "private-uncertain", "private-audio-path",
            "private-partial-transcript", "private-partial-coaching",
        ]
        let turn = VoiceTurnRecord(
            id: UUID().uuidString, conversationID: UUID().uuidString,
            transcriptionRequestID: UUID().uuidString, transcriptionIdempotencyKey: "t",
            coachingRequestID: UUID().uuidString, coachingIdempotencyKey: "c",
            state: .recoverableFailure, stage: .coaching,
            audioFileID: "private-audio-path", audioSHA256: "private-digest",
            acceptedTranscript: "private-transcript",
            uncertainTranscript: "private-uncertain",
            createdAtMS: 0, updatedAtMS: 0
        )
        let snapshot = VoiceSessionSnapshot(
            durable: turn,
            partialTranscript: "private-partial-transcript",
            partialCoaching: "private-partial-coaching"
        )

        let output = diagnosticText(snapshot)
        for value in forbidden { #expect(!output.contains(value)) }
        #expect(output.contains("redacted"))
    }

    private func diagnosticText(_ value: Any) -> String {
        var result = String(describing: value) + String(reflecting: value)
        dump(value, to: &result)
        debugPrint(value, to: &result)
        let mirror = Mirror(reflecting: value)
        for child in mirror.children {
            result += child.label ?? ""
            result += String(reflecting: child.value)
        }
        return result
    }
}
