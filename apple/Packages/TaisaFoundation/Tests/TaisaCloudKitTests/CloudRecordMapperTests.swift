import CloudKit
import Foundation
import Testing
import TaisaCloudKit
import TaisaSecurity
import TaisaSync

@Suite struct CloudRecordMapperTests {
    private let canary = "PRIVATE-CANARY-CAREER-MESSAGE"

    @Test func recordContainsOnlyOpaqueMetadataAndCiphertextAsset() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let change = EncryptedChange(
            id: id.uuidString,
            envelope: VaultEnvelope(
                version: 1,
                metadata: EnvelopeMetadata(vaultID: UUID(), recordID: id, entityType: "message", schemaVersion: 1, tombstone: false),
                ciphertext: Data(repeating: 0xA5, count: 64)
            )
        )
        let record = try CloudRecordMapper.makeRecord(change, assetDirectory: directory)
        #expect(record.recordID.zoneID.zoneName == "TaisaVaultV1")
        #expect(record.recordID.recordName == id.uuidString)
        #expect(Set(record.allKeys()) == ["vaultID", "entityType", "schemaVersion", "envelopeVersion", "tombstone", "ciphertext"])
        let visible = ([record.recordID.recordName, record.recordType] + record.allKeys() + record.allKeys().compactMap { record[$0]?.description }).joined(separator: " ")
        #expect(!visible.contains(canary))
        let asset = try #require(record["ciphertext"] as? CKAsset)
        let file = try #require(asset.fileURL)
        #expect(try Data(contentsOf: file) == change.envelope.ciphertext)
        #expect(try CloudRecordMapper.change(from: record) == change)
    }

    @Test func rejectsPrivateOrMalformedRecordNames() throws {
        let bad = EncryptedChange(id: canary, envelope: VaultEnvelope(version: 1, metadata: EnvelopeMetadata(vaultID: UUID(), recordID: UUID(), entityType: "message", schemaVersion: 1, tombstone: false), ciphertext: Data(repeating: 1, count: 32)))
        #expect(throws: CloudRecordMappingError.self) {
            _ = try CloudRecordMapper.makeRecord(bad, assetDirectory: FileManager.default.temporaryDirectory)
        }
    }
}
