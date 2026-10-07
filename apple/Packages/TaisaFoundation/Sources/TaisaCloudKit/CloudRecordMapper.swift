import CloudKit
import Foundation
import TaisaSecurity
import TaisaSync

public enum CloudRecordMappingError: Error, Sendable, CustomStringConvertible {
    case invalidRecord
    case invalidAsset

    public var description: String { "Invalid encrypted CloudKit record" }
}

/// The schema intentionally exposes only fixed labels and opaque identifiers.
/// Causal history and all user-authored values are inside the sealed asset.
public enum CloudRecordMapper {
    public static let zoneName = "TaisaVaultV1"
    public static let recordType = "TaisaEncryptedChangeV1"
    public static let fieldNames: Set<String> = [
        "vaultID", "entityType", "schemaVersion", "envelopeVersion", "tombstone", "ciphertext",
    ]
    private static let entityTypes: Set<String> = [
        "profile", "conversation", "message", "goal", "milestone", "action",
        "evidence", "memory", "memory_source", "weekly_placement", "work_event",
        "insight", "insight_source", "insight_revision", "snapshot",
    ]

    public static var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    public static func makeRecord(_ change: EncryptedChange, assetDirectory: URL) throws -> CKRecord {
        let envelope = change.envelope
        guard let id = UUID(uuidString: change.id), id.uuidString == change.id,
              id == envelope.metadata.recordID,
              envelope.version == 1, envelope.metadata.schemaVersion == 1,
              entityTypes.contains(envelope.metadata.entityType),
              envelope.ciphertext.count >= 28 else { throw CloudRecordMappingError.invalidRecord }
        let file = assetDirectory.appendingPathComponent(UUID().uuidString, isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: assetDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try envelope.ciphertext.write(to: file, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw CloudRecordMappingError.invalidAsset
        }
        let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: change.id, zoneID: zoneID))
        record["vaultID"] = envelope.metadata.vaultID.uuidString as NSString
        record["entityType"] = envelope.metadata.entityType as NSString
        record["schemaVersion"] = NSNumber(value: envelope.metadata.schemaVersion)
        record["envelopeVersion"] = NSNumber(value: envelope.version)
        record["tombstone"] = NSNumber(value: envelope.metadata.tombstone)
        record["ciphertext"] = CKAsset(fileURL: file)
        return record
    }

    public static func change(from record: CKRecord) throws -> EncryptedChange {
        guard record.recordType == recordType, record.recordID.zoneID == zoneID,
              Set(record.allKeys()) == fieldNames,
              let id = UUID(uuidString: record.recordID.recordName), id.uuidString == record.recordID.recordName,
              let vaultText = record["vaultID"] as? String,
              let vaultID = UUID(uuidString: vaultText), vaultID.uuidString == vaultText,
              let entityType = record["entityType"] as? String, entityTypes.contains(entityType),
              let schema = record["schemaVersion"] as? NSNumber, schema.intValue == 1,
              let version = record["envelopeVersion"] as? NSNumber, version.intValue == 1,
              let tombstone = record["tombstone"] as? NSNumber,
              tombstone.intValue == 0 || tombstone.intValue == 1,
              let asset = record["ciphertext"] as? CKAsset,
              let file = asset.fileURL else { throw CloudRecordMappingError.invalidRecord }
        let ciphertext: Data
        do { ciphertext = try Data(contentsOf: file) }
        catch { throw CloudRecordMappingError.invalidAsset }
        guard ciphertext.count >= 28 else { throw CloudRecordMappingError.invalidAsset }
        return EncryptedChange(
            id: id.uuidString,
            envelope: VaultEnvelope(
                version: version.intValue,
                metadata: EnvelopeMetadata(vaultID: vaultID, recordID: id, entityType: entityType,
                                           schemaVersion: schema.intValue, tombstone: tombstone.boolValue),
                ciphertext: ciphertext
            )
        )
    }
}
