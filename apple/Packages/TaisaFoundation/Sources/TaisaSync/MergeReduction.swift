import Foundation

/// A replayable, validated set of source events. Materialized fields are never
/// recast as one synthetic mutation, which would erase their causal ownership.
public struct SyncMergeState: Codable, Sendable, Equatable {
    public let events: [SyncMutation]
    fileprivate init(events: [SyncMutation]) { self.events = events }

    public init(from decoder: Decoder) throws {
        let events = try [SyncMutation](from: decoder)
        self = try MergeEngine.reduce(events: events).state
    }

    public func encode(to encoder: Encoder) throws {
        try events.encode(to: encoder)
    }
}

public struct SyncDeletionSummary: Codable, Sendable, Equatable {
    public let id: String
    public let eventIDs: [String]
    public let timestampMS: Int64
    public let frontier: VersionVector
    public let observedFieldVersions: [SyncObservedField]
    public let fieldAncestry: [String: [String]]?

    public init(id: String, eventIDs: [String], timestampMS: Int64, frontier: VersionVector, observedFieldVersions: [SyncObservedField], fieldAncestry: [String: [String]]? = nil) {
        self.id = id
        self.eventIDs = eventIDs
        self.timestampMS = timestampMS
        self.frontier = frontier
        self.observedFieldVersions = observedFieldVersions
        self.fieldAncestry = fieldAncestry
    }

    static func canonicalFieldAncestry(_ source: [String: [String]]?) throws -> [String: [String]]? {
        guard let source, !source.isEmpty else { return nil }
        var result: [String: [String]] = [:]
        for (name, raw) in source {
            guard !name.isEmpty, name != "__record", !raw.isEmpty else { throw SyncMergeError.malformedMutation }
            let ids = try raw.map { value in
                guard let id = UUID(uuidString: value)?.uuidString else { throw SyncMergeError.malformedMutation }
                return id
            }
            guard Set(ids).count == ids.count else { throw SyncMergeError.malformedMutation }
            result[name] = ids.sorted()
        }
        return result
    }

    func retaining(field: String, ancestry: [String]) throws -> SyncDeletionSummary {
        var map = fieldAncestry ?? [:]
        let ids = Set((map[field] ?? []) + ancestry).subtracting(eventIDs)
        if !ids.isEmpty { map[field] = ids.sorted() }
        return try SyncDeletionSummary(id: id, eventIDs: eventIDs, timestampMS: timestampMS, frontier: frontier, observedFieldVersions: observedFieldVersions, fieldAncestry: map).validated()
    }

    func validated() throws -> SyncDeletionSummary {
        guard let key = UUID(uuidString: id)?.uuidString,
              timestampMS >= 0, frontier.isValid, !frontier.entries.isEmpty,
              !eventIDs.isEmpty, eventIDs.allSatisfy({ UUID(uuidString: $0) != nil }),
              Set(eventIDs.compactMap { UUID(uuidString: $0) }).count == eventIDs.count,
              eventIDs.contains(where: { UUID(uuidString: $0) == UUID(uuidString: id) }),
              observedFieldVersions.allSatisfy({ !$0.name.isEmpty && UUID(uuidString: $0.versionID) != nil }) else { throw SyncMergeError.malformedMutation }
        return try SyncDeletionSummary(id: key, eventIDs: eventIDs.map { UUID(uuidString: $0)!.uuidString }.sorted(), timestampMS: timestampMS, frontier: frontier.canonicalized(), observedFieldVersions: observedFieldVersions.map { SyncObservedField(name: $0.name, versionID: UUID(uuidString: $0.versionID)!.uuidString) }.sorted { ($0.name, $0.versionID) < ($1.name, $1.versionID) }, fieldAncestry: Self.canonicalFieldAncestry(fieldAncestry))
    }
}

public struct MergeDecision: Sendable, Equatable {
    public enum Kind: Sendable { case applied, duplicate, noOp, merged, conflicted, deleted, deletedWithConflicts }
    public let kind: Kind
    public let fields: [SyncField]
    public let conflicts: [SyncConflict]
    public let deletion: SyncDeletionSummary?
    public let state: SyncMergeState
}

public enum MergeEngine {
    public static func merge(local: SyncMutation?, remote: SyncMutation) throws -> MergeDecision {
        try reduce(events: (local.map { [$0] } ?? []) + [remote])
    }

    public static func merge(state: SyncMergeState, remote: SyncMutation) throws -> MergeDecision {
        try reduce(events: state.events + [remote])
    }

    public static func reduce(events: [SyncMutation]) throws -> MergeDecision {
        guard !events.isEmpty else { throw SyncMergeError.malformedMutation }
        var unique: [String: SyncMutation] = [:]
        for source in events {
            try source.validate()
            let event = source.canonicalized()
            if let existing = unique[event.id] {
                guard existing == event else { throw SyncMergeError.malformedMutation }
            } else { unique[event.id] = event }
        }
        let ordered = unique.values.sorted { $0.id < $1.id }
        let first = ordered[0]
        guard ordered.allSatisfy({ $0.entityType == first.entityType && $0.entityID == first.entityID && $0.entityVersion == first.entityVersion }) else { throw SyncMergeError.identityMismatch }
        try validateGraph(ordered)
        let state = SyncMergeState(events: ordered)
        let duplicateDelivery = events.count > ordered.count

        if first.entityType == "message" || first.entityType == "memory_source" {
            let creates = ordered.filter { $0.kind == .create }
            let deletions = ordered.filter { $0.kind == .delete }
            if deletions.isEmpty {
                guard let exemplar = creates.first else { throw SyncMergeError.malformedMutation }
                let identical = creates.allSatisfy { candidate in
                    candidate.fields.count == exemplar.fields.count && zip(candidate.fields, exemplar.fields).allSatisfy { $0.name == $1.name && $0.value == $1.value }
                }
                if identical {
                    return MergeDecision(kind: duplicateDelivery || creates.count > 1 ? .duplicate : .applied, fields: exemplar.fields, conflicts: [], deletion: nil, state: state)
                }
                let names = Set(creates.flatMap { $0.fields.map(\.name) }).sorted()
                let alternatives = names.flatMap { name -> [SyncConflict] in
                    var result: [SyncConflict] = []
                    for left in 0..<(creates.count - 1) {
                        for right in (left + 1)..<creates.count {
                            let a = creates[left], b = creates[right]
                            let leftField = a.fields.first { $0.name == name }
                            let rightField = b.fields.first { $0.name == name }
                            if leftField?.value != rightField?.value {
                                result.append(makeConflict(first: first, name: name, a: (a, leftField), b: (b, rightField)))
                            }
                        }
                    }
                    return result
                }
                return MergeDecision(kind: .conflicted, fields: [], conflicts: alternatives, deletion: nil, state: state)
            }
        }

        let deletions = ordered.filter { $0.kind == .delete && !isSuperseded($0, by: ordered) }
        let deletion = try summarize(deletions, known: unique)
        let fieldNames = Set(ordered.flatMap { $0.fields.map(\.name) }).sorted()
        var winners: [SyncField] = []
        var conflicts: [SyncConflict] = []
        for name in fieldNames {
            let candidates = ordered.compactMap { event -> (SyncMutation, SyncField)? in
                guard let field = event.fields.first(where: { $0.name == name }) else { return nil }
                return (event, field)
            }
            let heads = candidates.filter { candidate in
                !candidates.contains { other in other.0.id != candidate.0.id && fieldDescends(other.1, name: name, from: candidate.0.id, in: unique) }
            }
            if let deletion {
                let observed = Set(deletion.observedFieldVersions.filter { $0.name == name }.map(\.versionID))
                for head in heads where !observed.contains(head.0.id) {
                    let unresolved = deletion.eventIDs.filter { !fieldDescends(head.1, name: name, from: $0, in: unique) }
                    guard let representative = unresolved.first else { continue }
                    conflicts.append(try makeDeletionConflict(first: first, name: name, edit: head, deletionID: representative, evidence: deletion).validated())
                }
            } else if heads.count == 1 {
                winners.append(heads[0].1)
            } else if heads.count > 1 {
                if heads.allSatisfy({ $0.1.value == heads[0].1.value }) {
                    winners.append(heads[0].1)
                    continue
                }
                for left in 0..<(heads.count - 1) {
                    for right in (left + 1)..<heads.count {
                        if heads[left].1.value != heads[right].1.value {
                            conflicts.append(makeConflict(first: first, name: name, a: heads[left], b: heads[right]))
                        }
                    }
                }
            }
        }
        conflicts.sort { ($0.fieldName, $0.first.versionID, $0.second.versionID) < ($1.fieldName, $1.first.versionID, $1.second.versionID) }
        let kind: MergeDecision.Kind
        if deletion != nil { kind = conflicts.isEmpty ? .deleted : .deletedWithConflicts }
        else if !conflicts.isEmpty { kind = .conflicted }
        else if duplicateDelivery { kind = .duplicate }
        else if ordered.count == 1 { kind = ordered[0].fields.isEmpty ? .noOp : .applied }
        else { kind = .merged }
        return MergeDecision(kind: kind, fields: deletion == nil ? winners.sorted { $0.name < $1.name } : [], conflicts: conflicts, deletion: deletion, state: state)
    }

    private static func validateGraph(_ events: [SyncMutation]) throws {
        var counters: [String: Set<Int64>] = [:]
        let known = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
        for event in events {
            guard counters[event.deviceID, default: []].insert(event.counter).inserted else { throw SyncMergeError.duplicateDeviceCounter }
            let parents = parentIDs(of: event)
            for parentID in parents {
                guard let parent = known[parentID] else { continue }
                for observed in event.observedFieldVersions where observed.versionID == parentID {
                    guard parent.fields.contains(where: { $0.name == observed.name }) else { throw SyncMergeError.malformedMutation }
                }
                for observed in event.retainedDeletionEvidence?.observedFieldVersions ?? [] where observed.versionID == parentID {
                    guard parent.fields.contains(where: { $0.name == observed.name }) else { throw SyncMergeError.malformedMutation }
                }
                for (name, ids) in event.retainedDeletionEvidence?.fieldAncestry ?? [:] where ids.contains(parentID) && parent.kind != .delete {
                    guard parent.fields.contains(where: { $0.name == name }) else { throw SyncMergeError.malformedMutation }
                }
                if event.fields.contains(where: { $0.ancestorVersionIDs.contains(parentID) }) && event.kind != .resolve && parent.kind != .delete {
                    for field in event.fields where field.ancestorVersionIDs.contains(parentID) {
                        guard parent.fields.contains(where: { $0.name == field.name }) else { throw SyncMergeError.malformedMutation }
                    }
                }
            }
        }
        var active: Set<String> = []
        var effective: [String: VersionVector] = [:]
        func visit(_ event: SyncMutation) throws -> VersionVector {
            if active.contains(event.id) { throw SyncMergeError.malformedMutation }
            if let cached = effective[event.id] { return cached }
            active.insert(event.id)
            var inherited = event.retainedDeletionEvidence?.frontier
            let parents = parentIDs(of: event)
            for parentID in parents {
                guard let parent = known[parentID] else { continue }
                let parentFrontier = try visit(parent)
                if parent.deviceID == event.deviceID && parent.counter >= event.counter { throw SyncMergeError.malformedMutation }
                inherited = inherited?.merged(with: parentFrontier) ?? parentFrontier
            }
            if let inherited {
                for entry in inherited.entries {
                    if let explicit = event.frontier.counter(for: entry.deviceID), explicit < entry.counter {
                        throw SyncMergeError.malformedMutation
                    }
                }
                if let own = inherited.counter(for: event.deviceID), own >= event.counter {
                    throw SyncMergeError.malformedMutation
                }
            }
            let closure = inherited.flatMap { event.frontier.merged(with: $0) } ?? event.frontier
            active.remove(event.id)
            effective[event.id] = closure
            return closure
        }
        for event in events { _ = try visit(event) }
    }

    private static func parentIDs(of event: SyncMutation) -> Set<String> {
        var parents = Set(event.fields.flatMap(\.ancestorVersionIDs))
        parents.formUnion(event.observedFieldVersions.map(\.versionID))
        if let record = event.recordParentVersionID { parents.insert(record) }
        parents.formUnion(event.resolvedParentVersionIDs ?? [])
        if let retained = event.retainedDeletionEvidence {
            parents.formUnion(retained.eventIDs)
            parents.formUnion(retained.observedFieldVersions.map(\.versionID))
            parents.formUnion((retained.fieldAncestry ?? [:]).values.flatMap { $0 })
        }
        return parents
    }

    private static func descends(_ child: SyncMutation, from ancestorID: String, in known: [String: SyncMutation]) -> Bool {
        var pending = child.fields.flatMap(\.ancestorVersionIDs) + (child.recordParentVersionID.map { [$0] } ?? []) + (child.resolvedParentVersionIDs ?? [])
        var seen: Set<String> = []
        while let parent = pending.popLast() {
            if parent == ancestorID { return true }
            if seen.insert(parent).inserted, let event = known[parent] {
                pending += event.fields.flatMap(\.ancestorVersionIDs) + (event.recordParentVersionID.map { [$0] } ?? []) + (event.resolvedParentVersionIDs ?? [])
            }
        }
        return false
    }

    private static func fieldDescends(_ child: SyncField, name: String, from ancestorID: String, in known: [String: SyncMutation]) -> Bool {
        var pending = child.ancestorVersionIDs
        var seen: Set<String> = []
        while let parent = pending.popLast() {
            if parent == ancestorID { return true }
            if seen.insert(parent).inserted, let event = known[parent], let field = event.fields.first(where: { $0.name == name }) {
                pending += field.ancestorVersionIDs
            }
        }
        return false
    }

    private static func isSuperseded(_ deletion: SyncMutation, by events: [SyncMutation]) -> Bool {
        let known = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
        return events.contains { event in
            guard event.id != deletion.id, descends(event, from: deletion.id, in: known) else { return false }
            if event.kind == .resolve {
                return !event.fields.isEmpty && event.fields.allSatisfy { fieldDescends($0, name: $0.name, from: deletion.id, in: known) }
            }
            return false
        }
    }

    private static func summarize(_ deletions: [SyncMutation], known: [String: SyncMutation]) throws -> SyncDeletionSummary? {
        guard let first = deletions.first else { return nil }
        var frontier = first.frontier
        var observed: [String: Set<String>] = [:]
        var eventIDs: Set<String> = []
        var fieldAncestry: [String: Set<String>] = [:]
        var latest = first.timestampMS
        for event in deletions {
            eventIDs.insert(event.id)
            guard let next = frontier.merged(with: event.frontier) else { throw SyncMergeError.malformedMutation }
            frontier = next
            latest = max(latest, event.timestampMS)
            for field in event.observedFieldVersions { observed[field.name, default: []].insert(field.versionID) }
            if let retained = event.retainedDeletionEvidence {
                let inherited = try retained.validated()
                eventIDs.formUnion(inherited.eventIDs)
                latest = max(latest, inherited.timestampMS)
                guard let inheritedFrontier = frontier.merged(with: inherited.frontier) else { throw SyncMergeError.malformedMutation }
                frontier = inheritedFrontier
                for field in inherited.observedFieldVersions { observed[field.name, default: []].insert(field.versionID) }
                for (name, ids) in inherited.fieldAncestry ?? [:] { fieldAncestry[name, default: []].formUnion(ids) }
            }
            // Legacy keep-deletion snapshots have one selected field and an
            // untagged parent list. Attribute that list only to the selected
            // field, never to observations inherited from other fields.
            if event.observedFieldVersions.count == 1, let name = event.observedFieldVersions.first?.name {
                fieldAncestry[name, default: []].formUnion(event.resolvedParentVersionIDs ?? [])
            }
        }
        for (name, versions) in observed {
            var pending = Array(versions)
            var seen: Set<String> = []
            while let id = pending.popLast() {
                guard seen.insert(id).inserted,
                      let field = known[id]?.fields.first(where: { $0.name == name }) else { continue }
                fieldAncestry[name, default: []].formUnion(field.ancestorVersionIDs)
                pending.append(contentsOf: field.ancestorVersionIDs)
            }
        }
        let retainedFields = fieldAncestry.reduce(into: [String: [String]]()) { result, pair in
            let ids = pair.value.subtracting(eventIDs)
            if !ids.isEmpty { result[pair.key] = ids.sorted() }
        }
        let orderedIDs = eventIDs.sorted()
        return SyncDeletionSummary(id: orderedIDs[0], eventIDs: orderedIDs, timestampMS: latest, frontier: frontier, observedFieldVersions: observed.keys.sorted().flatMap { name in observed[name]!.sorted().map { SyncObservedField(name: name, versionID: $0) } }, fieldAncestry: retainedFields.isEmpty ? nil : retainedFields)
    }

    private static func makeConflict(first: SyncMutation, name: String, a: (SyncMutation, SyncField?), b: (SyncMutation, SyncField?)) -> SyncConflict {
        let left = ConflictingValue(versionID: a.0.id, ancestorVersionIDs: a.1?.ancestorVersionIDs ?? a.0.resolvedParentVersionIDs ?? [], value: a.1?.value)
        let right = ConflictingValue(versionID: b.0.id, ancestorVersionIDs: b.1?.ancestorVersionIDs ?? b.0.resolvedParentVersionIDs ?? [], value: b.1?.value)
        let pair = left.versionID < right.versionID ? (left, right) : (right, left)
        return SyncConflict(entityType: first.entityType, entityID: first.entityID, fieldName: name, first: pair.0, second: pair.1)
    }

    private static func makeDeletionConflict(first: SyncMutation, name: String, edit: (SyncMutation, SyncField), deletionID: String, evidence: SyncDeletionSummary) -> SyncConflict {
        // Preserve the available history of this field's observed edits before
        // compaction. Record ordering and observations of unrelated fields are
        // causal evidence, not authority to overwrite this field.
        let observations = evidence.observedFieldVersions.filter { $0.name == name }
        var lineage = Set(evidence.eventIDs + observations.map(\.versionID) + (evidence.fieldAncestry?[name] ?? []))
        lineage.remove(deletionID)
        let edited = ConflictingValue(versionID: edit.0.id, ancestorVersionIDs: edit.1.ancestorVersionIDs, value: edit.1.value)
        let deleted = ConflictingValue(versionID: deletionID, ancestorVersionIDs: lineage.sorted(), value: nil, deletionEvidence: evidence)
        let pair = edited.versionID < deleted.versionID ? (edited, deleted) : (deleted, edited)
        return SyncConflict(entityType: first.entityType, entityID: first.entityID, fieldName: name, first: pair.0, second: pair.1)
    }
}
