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
        let conflict = try validated()
        guard conflict.entityType != "message", conflict.entityType != "memory_source" else { throw SyncMergeError.malformedMutation }
        let parents = conflict.ancestry
        let mutation = SyncMutation(id: mutationID, entityType: conflict.entityType, entityID: conflict.entityID, entityVersion: 1, deviceID: deviceID, counter: counter, timestampMS: timestampMS, kind: .resolve, fields: [SyncField(name: conflict.fieldName, value: value, versionID: mutationID, ancestorVersionIDs: parents, deviceCounter: counter)], recordParentVersionID: conflict.first.versionID, resolvedParentVersionIDs: parents)
        try mutation.validate()
        return mutation.canonicalized()
    }

    /// Explicitly keep the deletion, including both branches in its ancestry.
    public func resolveKeepingDeletion(mutationID: String, deviceID: String, counter: Int64, timestampMS: Int64) throws -> SyncMutation {
        let conflict = try validated()
        guard (conflict.first.value == nil) != (conflict.second.value == nil) else { throw SyncMergeError.malformedMutation }
        let edit = conflict.first.value == nil ? conflict.second : conflict.first
        let mutation = SyncMutation(id: mutationID, entityType: conflict.entityType, entityID: conflict.entityID, entityVersion: 1, deviceID: deviceID, counter: counter, timestampMS: timestampMS, kind: .delete, fields: [], observedFieldVersions: [SyncObservedField(name: conflict.fieldName, versionID: edit.versionID)], recordParentVersionID: conflict.first.versionID, resolvedParentVersionIDs: conflict.ancestry)
        try mutation.validate()
        return mutation.canonicalized()
    }

    private var ancestry: [String] {
        let immediate = [first.versionID, second.versionID]
        let transitive = Set(first.ancestorVersionIDs + second.ancestorVersionIDs).subtracting(immediate).sorted()
        return immediate + transitive
    }

    func validated() throws -> SyncConflict {
        guard let allowed = Self.fields[entityType], allowed.contains(fieldName),
              let entity = UUID(uuidString: entityID)?.uuidString,
              let firstID = UUID(uuidString: first.versionID)?.uuidString,
              let secondID = UUID(uuidString: second.versionID)?.uuidString,
              firstID != secondID, first.value != second.value || first.value == nil,
              first.value != nil || second.value != nil else { throw SyncMergeError.malformedMutation }
        func canonical(_ source: ConflictingValue, id: String) throws -> ConflictingValue {
            let ancestors = try source.ancestorVersionIDs.map { raw -> String in
                guard let value = UUID(uuidString: raw)?.uuidString, value != id else { throw SyncMergeError.malformedMutation }
                return value
            }
            guard Set(ancestors).count == ancestors.count else { throw SyncMergeError.malformedMutation }
            return ConflictingValue(versionID: id, ancestorVersionIDs: ancestors, value: source.value)
        }
        let a = try canonical(first, id: firstID)
        let b = try canonical(second, id: secondID)
        guard !a.ancestorVersionIDs.contains(secondID), !b.ancestorVersionIDs.contains(firstID) else { throw SyncMergeError.malformedMutation }
        let pair = firstID < secondID ? (a, b) : (b, a)
        return SyncConflict(entityType: entityType, entityID: entity, fieldName: fieldName, first: pair.0, second: pair.1)
    }

    private static let fields: [String: Set<String>] = [
        "profile": ["displayName", "headline", "biography", "updatedAtMS"],
        "conversation": ["title", "createdAtMS", "updatedAtMS"],
        "message": ["conversationID", "role", "body", "createdAtMS"],
        "goal": ["title", "detail", "status", "createdAtMS", "updatedAtMS"],
        "milestone": ["goalID", "title", "status", "targetAtMS", "updatedAtMS"],
        "action": ["goalID", "title", "detail", "status", "dueAtMS", "createdAtMS", "updatedAtMS"],
        "evidence": ["goalID", "actionID", "title", "detail", "occurredAtMS", "createdAtMS"],
        "memory": ["kind", "content", "status", "createdAtMS", "updatedAtMS"],
        "memory_source": ["memoryItemID", "sourceType", "sourceID", "createdAtMS"],
    ]
}

/// Conflict rows live in the already-encrypted SQLCipher store. The static
/// operations accept a caller-owned transaction for atomic Task 6 composition.
public struct ConflictStore: Sendable {
    private let store: TaisaStore

    public init(store: TaisaStore) { self.store = store }

    public func persist(_ conflict: SyncConflict, at timestampMS: Int64) async throws {
        let conflict = try conflict.validated()
        guard timestampMS >= 0 else { throw SyncMergeError.malformedMutation }
        do { try await store.write { db in try Self.persist(conflict, at: timestampMS, in: db) } }
        catch let error as SyncMergeError { throw error }
        catch { throw SyncMergeError.persistenceFailed }
    }

    /// Compose conflict persistence with the caller's domain/outbox/token write.
    public static func persist(_ conflict: SyncConflict, at timestampMS: Int64, in db: Database) throws {
        let conflict = try conflict.validated()
        guard timestampMS >= 0 else { throw SyncMergeError.malformedMutation }
        let first: Data
        let second: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            first = try encoder.encode(conflict.first)
            second = try encoder.encode(conflict.second)
        } catch { throw SyncMergeError.persistenceFailed }
        do {
            let rows = try Row.fetchAll(db, sql: "SELECT local_value, remote_value FROM conflicts WHERE entity_type = ? AND entity_id = ? COLLATE NOCASE AND field_name = ? AND local_version_id = ? COLLATE NOCASE AND remote_version_id = ? COLLATE NOCASE", arguments: [conflict.entityType, conflict.entityID, conflict.fieldName, conflict.first.versionID, conflict.second.versionID])
            guard rows.count <= 1 else { throw SyncMergeError.persistenceFailed }
            if let row = rows.first {
                let storedFirst: Data = row["local_value"]
                let storedSecond: Data = row["remote_value"]
                guard storedFirst == first, storedSecond == second else { throw SyncMergeError.persistenceFailed }
                return
            }
            try db.execute(sql: "INSERT INTO conflicts (id, entity_type, entity_id, field_name, local_version_id, remote_version_id, local_value, remote_value, created_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", arguments: [UUID().uuidString, conflict.entityType, conflict.entityID, conflict.fieldName, conflict.first.versionID, conflict.second.versionID, first, second, timestampMS])
        } catch let error as SyncMergeError { throw error }
        catch { throw SyncMergeError.persistenceFailed }
    }

    /// Marks an existing conflict resolved inside the caller's write transaction.
    /// The caller inserts the returned resolution into domain/outbox in the same closure.
    public static func resolve(_ conflict: SyncConflict, using mutation: SyncMutation, at timestampMS: Int64, in db: Database) throws {
        let conflict = try conflict.validated()
        try mutation.validate()
        let mutation = mutation.canonicalized()
        guard timestampMS >= 0, mutation.entityType == conflict.entityType, mutation.entityID == conflict.entityID,
              mutation.kind == .resolve || mutation.kind == .delete,
              (mutation.resolvedParentVersionIDs ?? []).contains(conflict.first.versionID),
              (mutation.resolvedParentVersionIDs ?? []).contains(conflict.second.versionID) else { throw SyncMergeError.malformedMutation }
        try db.execute(sql: "UPDATE conflicts SET resolved_at_ms = ? WHERE entity_type = ? AND entity_id = ? COLLATE NOCASE AND field_name = ? AND local_version_id = ? COLLATE NOCASE AND remote_version_id = ? COLLATE NOCASE AND resolved_at_ms IS NULL", arguments: [timestampMS, conflict.entityType, conflict.entityID, conflict.fieldName, conflict.first.versionID, conflict.second.versionID])
        guard db.changesCount == 1 else { throw SyncMergeError.persistenceFailed }
    }

    public func unresolved() async throws -> [SyncConflict] {
        do {
            return try await store.read { db in
                let rows = try Row.fetchAll(db, sql: "SELECT entity_type, entity_id, field_name, local_version_id, remote_version_id, local_value, remote_value FROM conflicts WHERE resolved_at_ms IS NULL ORDER BY entity_type, entity_id, field_name, local_version_id, remote_version_id")
                return try rows.map { row in
                    let first: Data = row["local_value"]
                    let second: Data = row["remote_value"]
                    let decoded = try SyncConflict(entityType: row["entity_type"], entityID: row["entity_id"], fieldName: row["field_name"], first: JSONDecoder().decode(ConflictingValue.self, from: first), second: JSONDecoder().decode(ConflictingValue.self, from: second)).validated()
                    guard UUID(uuidString: row["local_version_id"] as String)?.uuidString == decoded.first.versionID,
                          UUID(uuidString: row["remote_version_id"] as String)?.uuidString == decoded.second.versionID else { throw SyncMergeError.malformedMutation }
                    return decoded
                }
            }
        } catch { throw SyncMergeError.persistenceFailed }
    }
}
