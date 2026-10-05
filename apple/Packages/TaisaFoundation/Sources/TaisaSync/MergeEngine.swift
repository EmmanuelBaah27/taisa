import Foundation

public struct MergeDecision: Sendable, Equatable {
    public enum Kind: Sendable { case applied, duplicate, merged, conflicted, deleted, deletedWithConflicts }
    public let kind: Kind
    public let fields: [SyncField]
    public let conflicts: [SyncConflict]
    public let deletion: SyncMutation?
}

public enum MergeEngine {
    public static func merge(local: SyncMutation?, remote: SyncMutation) throws -> MergeDecision {
        try remote.validate()
        guard let local else {
            return MergeDecision(kind: remote.kind == .delete ? .deleted : .applied, fields: remote.fields.sorted(by: fieldOrder), conflicts: [], deletion: remote.kind == .delete ? remote : nil)
        }
        try local.validate()
        guard local.entityType == remote.entityType, UUID(uuidString: local.entityID) == UUID(uuidString: remote.entityID), local.entityVersion == remote.entityVersion else { throw SyncMergeError.identityMismatch }
        if UUID(uuidString: local.id) == UUID(uuidString: remote.id) {
            guard local == remote else { throw SyncMergeError.malformedMutation }
            return MergeDecision(kind: .duplicate, fields: local.fields.sorted(by: fieldOrder), conflicts: [], deletion: local.kind == .delete ? local : nil)
        }
        if UUID(uuidString: local.deviceID) == UUID(uuidString: remote.deviceID) && local.counter == remote.counter { throw SyncMergeError.duplicateDeviceCounter }

        if local.kind == .delete || remote.kind == .delete {
            return mergeDeletion(local, remote)
        }
        if local.entityType == "message" || local.entityType == "memory_source" {
            // Append-only records cannot be edited under a reused identity.
            return mergeAppendOnly(local, remote)
        }
        var winners: [SyncField] = []
        var conflicts: [SyncConflict] = []
        let names = Set(local.fields.map(\.name)).union(remote.fields.map(\.name)).sorted()
        for name in names {
            let left = local.fields.first { $0.name == name }
            let right = remote.fields.first { $0.name == name }
            switch (left, right) {
            case (let a?, nil): winners.append(a)
            case (nil, let b?): winners.append(b)
            case (let a?, let b?):
                if sameID(a.versionID, b.versionID) {
                    guard a == b else { throw SyncMergeError.malformedMutation }
                    winners.append(a)
                } else if a.ancestorVersionIDs.contains(where: { sameID($0, b.versionID) }) {
                    winners.append(a)
                } else if b.ancestorVersionIDs.contains(where: { sameID($0, a.versionID) }) {
                    winners.append(b)
                } else {
                    conflicts.append(conflict(local, remote, name: name, left: a, right: b))
                }
            case (nil, nil): break
            }
        }
        return MergeDecision(kind: conflicts.isEmpty ? .merged : .conflicted, fields: winners.sorted(by: fieldOrder), conflicts: conflicts, deletion: nil)
    }

    private static func mergeAppendOnly(_ local: SyncMutation, _ remote: SyncMutation) -> MergeDecision {
        let leftFields = local.fields.sorted(by: fieldOrder)
        let rightFields = remote.fields.sorted(by: fieldOrder)
        if local.kind == .create, remote.kind == .create,
           leftFields.count == rightFields.count,
           zip(leftFields, rightFields).allSatisfy({ $0.name == $1.name && $0.value == $1.value }) {
            let chosen = local.id < remote.id ? leftFields : rightFields
            return MergeDecision(kind: .duplicate, fields: chosen, conflicts: [], deletion: nil)
        }
        let names = Set(local.fields.map(\.name)).union(remote.fields.map(\.name)).sorted()
        let conflicts = names.map { name in
            conflict(local, remote, name: name, left: local.fields.first { $0.name == name }, right: remote.fields.first { $0.name == name })
        }
        return MergeDecision(kind: .conflicted, fields: [], conflicts: conflicts.sorted { $0.fieldName < $1.fieldName }, deletion: nil)
    }

    private static func mergeDeletion(_ local: SyncMutation, _ remote: SyncMutation) -> MergeDecision {
        let deletes = [local, remote].filter { $0.kind == .delete }.sorted { $0.id < $1.id }
        let deletion = deletes[0]
        guard deletes.count == 1 else { return MergeDecision(kind: .deleted, fields: [], conflicts: [], deletion: deletion) }
        let edit = local.kind == .delete ? remote : local
        if edit.kind == .resolve && edit.fields.allSatisfy({ field in field.ancestorVersionIDs.contains(where: { sameID($0, deletion.id) }) }) {
            return MergeDecision(kind: .merged, fields: edit.fields.sorted(by: fieldOrder), conflicts: [], deletion: nil)
        }
        let observed = Dictionary(uniqueKeysWithValues: deletion.observedFieldVersions.map { ($0.name, $0.versionID) })
        let conflicts = edit.fields.filter { field in
            let seen = observed[field.name]
            return seen.map { !sameID($0, field.versionID) } ?? true
        }.map { field in conflict(edit, deletion, name: field.name, left: field, right: nil) }
        return MergeDecision(kind: conflicts.isEmpty ? .deleted : .deletedWithConflicts, fields: [], conflicts: conflicts.sorted { $0.fieldName < $1.fieldName }, deletion: deletion)
    }

    private static func conflict(_ local: SyncMutation, _ remote: SyncMutation, name: String, left: SyncField?, right: SyncField?) -> SyncConflict {
        let a = ConflictingValue(versionID: left?.versionID ?? local.id, ancestorVersionIDs: left?.ancestorVersionIDs ?? [], value: left?.value)
        let b = ConflictingValue(versionID: right?.versionID ?? remote.id, ancestorVersionIDs: right?.ancestorVersionIDs ?? [], value: right?.value)
        let ordered = (UUID(uuidString: a.versionID)?.uuidString ?? a.versionID) < (UUID(uuidString: b.versionID)?.uuidString ?? b.versionID) ? (a, b) : (b, a)
        return SyncConflict(entityType: local.entityType, entityID: local.entityID, fieldName: name, first: ordered.0, second: ordered.1)
    }

    private static func fieldOrder(_ a: SyncField, _ b: SyncField) -> Bool { a.name < b.name }
    private static func sameID(_ a: String, _ b: String) -> Bool { UUID(uuidString: a) == UUID(uuidString: b) }
}
