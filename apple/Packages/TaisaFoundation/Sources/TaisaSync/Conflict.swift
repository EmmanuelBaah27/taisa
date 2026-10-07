import Foundation
import GRDB
import TaisaStorage

public struct ConflictingValue: Codable, Sendable, Equatable {
    public let versionID: String
    public let ancestorVersionIDs: [String]
    /// Nil identifies a deletion. A non-nil Data is the preserved value.
    public let value: Data?
    public let deletionEvidence: SyncDeletionSummary?

    public init(versionID: String, ancestorVersionIDs: [String], value: Data?, deletionEvidence: SyncDeletionSummary? = nil) {
        self.versionID = versionID
        self.ancestorVersionIDs = ancestorVersionIDs
        self.value = value
        self.deletionEvidence = deletionEvidence
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
        guard !["message", "memory_source", "work_event", "insight_source"].contains(conflict.entityType) else { throw SyncMergeError.malformedMutation }
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
        let deletion = conflict.first.value == nil ? conflict.first : conflict.second
        let retained = try deletion.deletionEvidence?.retaining(field: conflict.fieldName, ancestry: conflict.ancestry)
        let mutation = SyncMutation(id: mutationID, entityType: conflict.entityType, entityID: conflict.entityID, entityVersion: 1, deviceID: deviceID, counter: counter, timestampMS: timestampMS, kind: .delete, fields: [], observedFieldVersions: [SyncObservedField(name: conflict.fieldName, versionID: edit.versionID)], recordParentVersionID: conflict.first.versionID, resolvedParentVersionIDs: conflict.ancestry, retainedDeletionEvidence: retained)
        try mutation.validate()
        return mutation.canonicalized()
    }

    fileprivate var ancestry: [String] {
        let immediate = [first.versionID, second.versionID]
        let deletions = (first.deletionEvidence?.eventIDs ?? []) + (second.deletionEvidence?.eventIDs ?? [])
        let transitive = Set(first.ancestorVersionIDs + second.ancestorVersionIDs + deletions).subtracting(immediate).sorted()
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
            guard source.value == nil || source.deletionEvidence == nil else { throw SyncMergeError.malformedMutation }
            let evidence = try source.deletionEvidence?.validated()
            if let evidence {
                guard evidence.eventIDs.contains(id), (evidence.fieldAncestry ?? [:]).keys.allSatisfy(allowed.contains) else { throw SyncMergeError.malformedMutation }
            }
            return ConflictingValue(versionID: id, ancestorVersionIDs: ancestors, value: source.value, deletionEvidence: evidence)
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
        "weekly_placement": ["actionID", "weekStartMS", "plannedDayMS", "createdAtMS", "updatedAtMS"],
        "work_event": ["actionID", "kind", "fromWeekStartMS", "toWeekStartMS", "sourceType", "sourceID", "occurredAtMS"],
        "insight": ["body", "status", "isTimeSensitive", "homeEligibleUntilMS", "createdAtMS", "updatedAtMS"],
        "insight_source": ["insightID", "sourceType", "sourceID", "excerpt", "createdAtMS"],
        "insight_revision": ["insightID", "proposedBody", "status", "sourceType", "sourceID", "createdAtMS", "resolvedAtMS"],
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
        do {
            let rows = try Row.fetchAll(db, sql: "SELECT id, local_value, remote_value, resolved_at_ms FROM conflicts WHERE entity_type = ? AND entity_id = ? COLLATE NOCASE AND field_name = ? AND local_version_id = ? COLLATE NOCASE AND remote_version_id = ? COLLATE NOCASE", arguments: [conflict.entityType, conflict.entityID, conflict.fieldName, conflict.first.versionID, conflict.second.versionID])
            guard rows.count <= 1 else { throw SyncMergeError.persistenceFailed }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            if let row = rows.first {
                let storedFirst: Data = row["local_value"]
                let storedSecond: Data = row["remote_value"]
                let stored = try SyncConflict(entityType: conflict.entityType, entityID: conflict.entityID, fieldName: conflict.fieldName, first: JSONDecoder().decode(ConflictingValue.self, from: storedFirst), second: JSONDecoder().decode(ConflictingValue.self, from: storedSecond)).validated()
                let enriched = try enrich(stored, with: conflict)
                let resolvedAt: Int64? = row["resolved_at_ms"]
                if resolvedAt != nil {
                    guard enriched == stored else { throw SyncMergeError.alreadyResolved }
                    return
                }
                let first = try encoder.encode(enriched.first)
                let second = try encoder.encode(enriched.second)
                if storedFirst != first || storedSecond != second {
                    try db.execute(sql: "UPDATE conflicts SET local_value = ?, remote_value = ? WHERE id = ? AND local_value = ? AND remote_value = ? AND resolved_at_ms IS NULL", arguments: [first, second, row["id"] as String, storedFirst, storedSecond])
                    guard db.changesCount == 1 else { throw SyncMergeError.persistenceFailed }
                }
                return
            }
            let first = try encoder.encode(conflict.first)
            let second = try encoder.encode(conflict.second)
            try db.execute(sql: "INSERT INTO conflicts (id, entity_type, entity_id, field_name, local_version_id, remote_version_id, local_value, remote_value, created_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", arguments: [UUID().uuidString, conflict.entityType, conflict.entityID, conflict.fieldName, conflict.first.versionID, conflict.second.versionID, first, second, timestampMS])
        } catch let error as SyncMergeError { throw error }
        catch { throw SyncMergeError.persistenceFailed }
    }

    private static func enrich(_ stored: SyncConflict, with incoming: SyncConflict) throws -> SyncConflict {
        guard stored.entityType == incoming.entityType, stored.entityID == incoming.entityID,
              stored.fieldName == incoming.fieldName else { throw SyncMergeError.persistenceFailed }
        func alternative(_ old: ConflictingValue, _ new: ConflictingValue) throws -> ConflictingValue {
            guard old.versionID == new.versionID, old.value == new.value else { throw SyncMergeError.persistenceFailed }
            let ancestry = mergeAncestry(old.ancestorVersionIDs, new.ancestorVersionIDs)
            let evidence: SyncDeletionSummary?
            switch (old.deletionEvidence, new.deletionEvidence) {
            case (nil, nil): evidence = nil
            case (let existing?, nil): evidence = existing
            case (nil, let added?): evidence = added
            case (let existing?, let added?):
                guard existing.id == added.id else { throw SyncMergeError.persistenceFailed }
                func includes(_ richer: SyncDeletionSummary, _ poorer: SyncDeletionSummary) -> Bool {
                    guard Set(poorer.eventIDs).isSubset(of: Set(richer.eventIDs)),
                          richer.timestampMS >= poorer.timestampMS,
                          Set(poorer.observedFieldVersions.map { "\($0.name):\($0.versionID)" }).isSubset(of: Set(richer.observedFieldVersions.map { "\($0.name):\($0.versionID)" })) else { return false }
                    return poorer.frontier.entries.allSatisfy { entry in
                        (richer.frontier.counter(for: entry.deviceID) ?? 0) >= entry.counter
                    }
                }
                if existing.eventIDs == added.eventIDs {
                    guard existing.id == added.id, existing.timestampMS == added.timestampMS,
                          existing.frontier == added.frontier, existing.observedFieldVersions == added.observedFieldVersions else { throw SyncMergeError.persistenceFailed }
                    evidence = SyncDeletionSummary(id: existing.id, eventIDs: existing.eventIDs, timestampMS: existing.timestampMS, frontier: existing.frontier, observedFieldVersions: existing.observedFieldVersions, fieldAncestry: mergeFieldAncestry(existing.fieldAncestry, added.fieldAncestry))
                } else {
                    let oldIDs = Set(existing.eventIDs)
                    let newIDs = Set(added.eventIDs)
                    if oldIDs.isSubset(of: newIDs) && !includes(added, existing) { throw SyncMergeError.persistenceFailed }
                    if newIDs.isSubset(of: oldIDs) && !includes(existing, added) { throw SyncMergeError.persistenceFailed }
                    let ids = Array(Set(existing.eventIDs + added.eventIDs)).sorted()
                    guard let frontier = existing.frontier.merged(with: added.frontier) else { throw SyncMergeError.persistenceFailed }
                    var observations: [String: Set<String>] = [:]
                    for item in existing.observedFieldVersions + added.observedFieldVersions {
                        observations[item.name, default: []].insert(item.versionID)
                    }
                    let observed = observations.keys.sorted().flatMap { name in
                        observations[name]!.sorted().map { SyncObservedField(name: name, versionID: $0) }
                    }
                    evidence = try SyncDeletionSummary(id: ids[0], eventIDs: ids, timestampMS: max(existing.timestampMS, added.timestampMS), frontier: frontier, observedFieldVersions: observed, fieldAncestry: mergeFieldAncestry(existing.fieldAncestry, added.fieldAncestry)).validated()
                }
            }
            return ConflictingValue(versionID: old.versionID, ancestorVersionIDs: ancestry, value: old.value, deletionEvidence: evidence)
        }
        return try SyncConflict(entityType: stored.entityType, entityID: stored.entityID, fieldName: stored.fieldName, first: alternative(stored.first, incoming.first), second: alternative(stored.second, incoming.second)).validated()
    }

    private static func mergeFieldAncestry(_ first: [String: [String]]?, _ second: [String: [String]]?) -> [String: [String]]? {
        var map = first ?? [:]
        for (name, ids) in second ?? [:] { map[name] = Set((map[name] ?? []) + ids).sorted() }
        return map.isEmpty ? nil : map
    }

    /// Ancestry identifies known parents; array position is not a causal edge.
    /// Retain the richer supplied representation unchanged when possible, so
    /// exact or poorer delivery never rewrites an existing conflict.
    private static func mergeAncestry(_ existing: [String], _ incoming: [String]) -> [String] {
        let oldIDs = Set(existing), newIDs = Set(incoming)
        if newIDs.isSubset(of: oldIDs) { return existing }
        if oldIDs.isSubset(of: newIDs) { return incoming }
        return oldIDs.union(newIDs).sorted()
    }

    private static func equivalent(_ stored: SyncConflict, _ incoming: SyncConflict) -> Bool {
        func alternative(_ old: ConflictingValue, _ new: ConflictingValue) -> Bool {
            old.versionID == new.versionID && old.value == new.value &&
                old.deletionEvidence == new.deletionEvidence &&
                Set(old.ancestorVersionIDs) == Set(new.ancestorVersionIDs)
        }
        return stored.entityType == incoming.entityType && stored.entityID == incoming.entityID &&
            stored.fieldName == incoming.fieldName &&
            alternative(stored.first, incoming.first) && alternative(stored.second, incoming.second)
    }

    /// Marks an existing conflict resolved inside the caller's write transaction.
    /// The caller inserts the returned resolution into domain/outbox in the same closure.
    public static func resolve(_ conflict: SyncConflict, using mutation: SyncMutation, at timestampMS: Int64, in db: Database) throws {
        let conflict = try conflict.validated()
        try mutation.validate()
        let mutation = mutation.canonicalized()
        let lineage = Set(conflict.ancestry)
        guard timestampMS >= 0, mutation.entityType == conflict.entityType, mutation.entityID == conflict.entityID,
              mutation.kind == .resolve || mutation.kind == .delete,
              Set(mutation.resolvedParentVersionIDs ?? []) == lineage,
              mutation.recordParentVersionID == conflict.first.versionID || mutation.recordParentVersionID == conflict.second.versionID else { throw SyncMergeError.malformedMutation }
        switch mutation.kind {
        case .resolve:
            guard mutation.fields.count == 1, let field = mutation.fields.first,
                  field.name == conflict.fieldName, Set(field.ancestorVersionIDs) == lineage,
                  mutation.retainedDeletionEvidence == nil else { throw SyncMergeError.malformedMutation }
        case .delete:
            guard (conflict.first.value == nil) != (conflict.second.value == nil) else { throw SyncMergeError.malformedMutation }
            let edited = conflict.first.value == nil ? conflict.second : conflict.first
            let deleting = conflict.first.value == nil ? conflict.first : conflict.second
            guard mutation.observedFieldVersions.contains(where: { $0.name == conflict.fieldName && $0.versionID == edited.versionID }),
                  mutation.retainedDeletionEvidence == (try deleting.deletionEvidence?.retaining(field: conflict.fieldName, ancestry: conflict.ancestry)) else { throw SyncMergeError.malformedMutation }
        default: throw SyncMergeError.malformedMutation
        }
        do {
            let rows = try Row.fetchAll(db, sql: "SELECT local_value, remote_value FROM conflicts WHERE entity_type = ? AND entity_id = ? COLLATE NOCASE AND field_name = ? AND local_version_id = ? COLLATE NOCASE AND remote_version_id = ? COLLATE NOCASE AND resolved_at_ms IS NULL", arguments: [conflict.entityType, conflict.entityID, conflict.fieldName, conflict.first.versionID, conflict.second.versionID])
            guard rows.count == 1 else { throw SyncMergeError.persistenceFailed }
            let storedFirst: Data = rows[0]["local_value"]
            let storedSecond: Data = rows[0]["remote_value"]
            let stored = try SyncConflict(entityType: conflict.entityType, entityID: conflict.entityID, fieldName: conflict.fieldName, first: JSONDecoder().decode(ConflictingValue.self, from: storedFirst), second: JSONDecoder().decode(ConflictingValue.self, from: storedSecond)).validated()
            guard equivalent(stored, conflict) else { throw SyncMergeError.malformedMutation }
        } catch let error as SyncMergeError { throw error }
        catch { throw SyncMergeError.persistenceFailed }
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
