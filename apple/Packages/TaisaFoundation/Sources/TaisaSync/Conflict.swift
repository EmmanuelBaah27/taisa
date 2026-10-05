import Foundation
import GRDB
import TaisaStorage

public struct ConflictingValue: Codable, Sendable, Equatable {
    public let versionID: String
    public let ancestorVersionIDs: [String]
    /// Nil identifies a deletion. A non-nil Data is the preserved value.
    public let value: Data?

    public init(versionID: String, ancestorVersionIDs: [String], value: Data?) {
        self.versionID = versionID
        self.ancestorVersionIDs = ancestorVersionIDs
        self.value = value
    }
}

public struct SyncConflict: Codable, Sendable, Equatable {
    public let entityType: String
    public let entityID: String
    public let fieldName: String
    public let first: ConflictingValue
    public let second: ConflictingValue

    public init(entityType: String, entityID: String, fieldName: String, first: ConflictingValue, second: ConflictingValue) {
        self.entityType = entityType
        self.entityID = entityID
        self.fieldName = fieldName
        self.first = first
        self.second = second
    }

    /// Explicit resolution is a new outgoing mutation with both parents.
    public func resolve(value: Data, mutationID: String, deviceID: String, counter: Int64, timestampMS: Int64) throws -> SyncMutation {
        guard entityType != "message", entityType != "memory_source" else { throw SyncMergeError.malformedMutation }
        let parents = [first.versionID, second.versionID]
        let mutation = SyncMutation(id: mutationID, entityType: entityType, entityID: entityID, entityVersion: 1, deviceID: deviceID, counter: counter, timestampMS: timestampMS, kind: .resolve, fields: [SyncField(name: fieldName, value: value, versionID: mutationID, ancestorVersionIDs: parents, deviceCounter: counter)], recordParentVersionID: first.versionID)
        try mutation.validate()
        return mutation
    }
}

/// Conflict rows live in the already-encrypted SQLCipher store. The public
/// surface carries domain values only; GRDB stays an implementation detail.
public struct ConflictStore: Sendable {
    private let store: TaisaStore

    public init(store: TaisaStore) { self.store = store }

    public func persist(_ conflict: SyncConflict, at timestampMS: Int64) async throws {
        guard timestampMS >= 0,
              let canonicalEntityID = UUID(uuidString: conflict.entityID)?.uuidString,
              let firstID = UUID(uuidString: conflict.first.versionID)?.uuidString,
              let secondID = UUID(uuidString: conflict.second.versionID)?.uuidString,
              firstID < secondID, !conflict.entityType.isEmpty, !conflict.fieldName.isEmpty else { throw SyncMergeError.malformedMutation }
        let first: Data
        let second: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            first = try encoder.encode(conflict.first)
            second = try encoder.encode(conflict.second)
        } catch { throw SyncMergeError.persistenceFailed }
        do {
            try await store.write { db in
                let rows = try Row.fetchAll(db, sql: "SELECT local_value, remote_value FROM conflicts WHERE entity_type = ? AND entity_id = ? COLLATE NOCASE AND field_name = ? AND local_version_id = ? COLLATE NOCASE AND remote_version_id = ? COLLATE NOCASE", arguments: [conflict.entityType, canonicalEntityID, conflict.fieldName, firstID, secondID])
                guard rows.count <= 1 else { throw SyncMergeError.persistenceFailed }
                if let row = rows.first {
                    let storedFirst: Data = row["local_value"]
                    let storedSecond: Data = row["remote_value"]
                    guard storedFirst == first, storedSecond == second else { throw SyncMergeError.persistenceFailed }
                    return
                }
                try db.execute(sql: "INSERT INTO conflicts (id, entity_type, entity_id, field_name, local_version_id, remote_version_id, local_value, remote_value, created_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", arguments: [UUID().uuidString, conflict.entityType, conflict.entityID, conflict.fieldName, conflict.first.versionID, conflict.second.versionID, first, second, timestampMS])
            }
        } catch let error as SyncMergeError { throw error }
        catch { throw SyncMergeError.persistenceFailed }
    }

    public func unresolved() async throws -> [SyncConflict] {
        do {
            return try await store.read { db in
                let rows = try Row.fetchAll(db, sql: "SELECT entity_type, entity_id, field_name, local_value, remote_value FROM conflicts WHERE resolved_at_ms IS NULL ORDER BY entity_type, entity_id, field_name, local_version_id, remote_version_id")
                return try rows.map { row in
                    let first: Data = row["local_value"]
                    let second: Data = row["remote_value"]
                    return SyncConflict(entityType: row["entity_type"], entityID: row["entity_id"], fieldName: row["field_name"], first: try JSONDecoder().decode(ConflictingValue.self, from: first), second: try JSONDecoder().decode(ConflictingValue.self, from: second))
                }
            }
        } catch { throw SyncMergeError.persistenceFailed }
    }
}
