import Foundation
import Testing
import TaisaStorage
@testable import TaisaSync

private actor Round2Keys: DatabaseKeyStore {
    var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ value: Data) async throws { key = value }
}

@Suite(.serialized) struct Round2IndependentProbes {
    let entity = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
    let a = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    let b = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    let c = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    let d = "99999999-9999-4999-8999-999999999999"
    func id(_ n: Int) -> String { String(format: "dddddddd-dddd-4ddd-8ddd-%012d", n) }
    func edit(_ n: Int, _ device: String, _ counter: Int64 = 1, _ parents: [String] = []) -> SyncMutation {
        SyncMutation(id: id(n), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: device, counter: counter, timestampMS: 1, kind: .update, fields: [SyncField(name: "title", value: Data("synthetic-\(n)".utf8), versionID: id(n), ancestorVersionIDs: parents, deviceCounter: counter)])
    }
    func deletion(_ n: Int, _ device: String, _ counter: Int64 = 1, observed: [SyncObservedField] = []) -> SyncMutation {
        SyncMutation(id: id(n), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: device, counter: counter, timestampMS: 1, kind: .delete, fields: [], observedFieldVersions: observed)
    }
    func store() async throws -> TaisaStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try await TaisaStore.open(at: directory.appendingPathComponent("probe.sqlite"), keyStore: Round2Keys())
    }

    @Test func transitiveKnownCounterRegressionWithSparseFrontierRejects() throws {
        let old = edit(1, a, 8)
        let middle = edit(2, b, 1, [id(1)])
        let child = edit(3, a, 2, [id(2)])
        #expect(throws: SyncMergeError.self) { try MergeEngine.reduce(events: [old, middle, child]) }
    }

    @Test func compactedRetainedFrontierCannotBeRegressedByEditableResolution() throws {
        let old = deletion(1, a, 8)
        let e = edit(2, b)
        let initial = try #require(MergeEngine.reduce(events: [old,e]).conflicts.first)
        let kept = try initial.resolveKeepingDeletion(mutationID: id(3), deviceID: b, counter: 2, timestampMS: 2)
        let later = edit(4, c)
        let next = try #require(MergeEngine.reduce(events: [kept,later]).conflicts.first)
        let impossible = try next.resolve(value: Data("chosen".utf8), mutationID: id(5), deviceID: a, counter: 2, timestampMS: 3)
        #expect(throws: SyncMergeError.self) { try MergeEngine.reduce(events: [kept,later,impossible]) }
    }

    @Test func evolvingDeletionEvidenceCanPersistExistingConflict() async throws {
        let db = try await store()
        let first = deletion(1,a)
        let e = edit(2,b)
        let initial = try #require(MergeEngine.reduce(events: [first,e]).conflicts.first)
        let conflicts = ConflictStore(store: db)
        try await conflicts.persist(initial, at: 1)
        let newer = deletion(3,c)
        let expanded = try #require(MergeEngine.reduce(events: [first,e,newer]).conflicts.first)
        #expect(initial.first.versionID == expanded.first.versionID)
        #expect(initial.second.versionID == expanded.second.versionID)
        try await conflicts.persist(expanded, at: 2)
        #expect(try await conflicts.unresolved() == [expanded])
    }

    @Test func independentEvidenceArrivalsUnionAndReplayIsIdempotent() async throws {
        let db = try await store()
        let conflicts = ConflictStore(store: db)
        let first = deletion(1,a)
        let e = edit(2,b)
        let third = deletion(3,c)
        let fourth = deletion(4,d)
        let left = try #require(MergeEngine.reduce(events: [first,e,third]).conflicts.first)
        let right = try #require(MergeEngine.reduce(events: [first,e,fourth]).conflicts.first)
        let all = try #require(MergeEngine.reduce(events: [first,e,third,fourth]).conflicts.first)
        try await conflicts.persist(left, at: 1)
        try await conflicts.persist(right, at: 2)
        #expect(try await conflicts.unresolved() == [all])
        try await conflicts.persist(left, at: 3)
        try await conflicts.persist(right, at: 4)
        #expect(try await conflicts.unresolved() == [all])
    }

    @Test func contradictorySameEvidenceAndChangedValueRejectWithoutMutation() async throws {
        let db = try await store()
        let conflicts = ConflictStore(store: db)
        let original = try #require(MergeEngine.reduce(events: [deletion(1,a),edit(2,b)]).conflicts.first)
        try await conflicts.persist(original, at: 1)
        let deleting = original.first.value == nil ? original.first : original.second
        let summary = try #require(deleting.deletionEvidence)
        let tampered = SyncDeletionSummary(id: summary.id, eventIDs: summary.eventIDs, timestampMS: summary.timestampMS + 10, frontier: summary.frontier, observedFieldVersions: summary.observedFieldVersions)
        let changed = ConflictingValue(versionID: deleting.versionID, ancestorVersionIDs: deleting.ancestorVersionIDs, value: nil, deletionEvidence: tampered)
        let altered = SyncConflict(entityType: original.entityType, entityID: original.entityID, fieldName: original.fieldName, first: original.first.value == nil ? changed : original.first, second: original.second.value == nil ? changed : original.second)
        await #expect(throws: SyncMergeError.self) { try await conflicts.persist(altered, at: 2) }
        let expanded = try #require(MergeEngine.reduce(events: [deletion(1,a),edit(2,b),deletion(3,c)]).conflicts.first)
        let expandedDeletion = expanded.first.value == nil ? expanded.first : expanded.second
        let expandedSummary = try #require(expandedDeletion.deletionEvidence)
        let regressing = SyncDeletionSummary(id: expandedSummary.id, eventIDs: expandedSummary.eventIDs, timestampMS: 0, frontier: expandedSummary.frontier, observedFieldVersions: expandedSummary.observedFieldVersions)
        let regressedAlternative = ConflictingValue(versionID: expandedDeletion.versionID, ancestorVersionIDs: expandedDeletion.ancestorVersionIDs, value: nil, deletionEvidence: regressing)
        let regressedConflict = SyncConflict(entityType: original.entityType, entityID: original.entityID, fieldName: original.fieldName, first: expanded.first.value == nil ? regressedAlternative : expanded.first, second: expanded.second.value == nil ? regressedAlternative : expanded.second)
        await #expect(throws: SyncMergeError.self) { try await conflicts.persist(regressedConflict, at: 3) }
        let editAlt = original.first.value == nil ? original.second : original.first
        let newValue = ConflictingValue(versionID: editAlt.versionID, ancestorVersionIDs: editAlt.ancestorVersionIDs, value: Data("contradiction".utf8))
        let changedEdit = SyncConflict(entityType: original.entityType, entityID: original.entityID, fieldName: original.fieldName, first: original.first.value == nil ? original.first : newValue, second: original.second.value == nil ? original.second : newValue)
        await #expect(throws: SyncMergeError.self) { try await conflicts.persist(changedEdit, at: 4) }
        #expect(try await conflicts.unresolved() == [original])
    }

    @Test func compactedAndFullConflictAlternativesConverge() throws {
        let old = deletion(1,a)
        let e = edit(2,b)
        let conflict = try #require(MergeEngine.reduce(events: [old,e]).conflicts.first)
        let kept = try conflict.resolveKeepingDeletion(mutationID: id(3), deviceID: b, counter: 2, timestampMS: 2)
        let newer = edit(4,c)
        let full = try MergeEngine.reduce(events: [old,e,kept,newer])
        let compact = try MergeEngine.reduce(events: [kept,newer])
        #expect(full.deletion == compact.deletion)
        #expect(full.conflicts == compact.conflicts)
    }

    @Test func retainedObservationsParticipateInCausalCycles() throws {
        let old = deletion(1,a)
        let summary = try #require(MergeEngine.reduce(events: [old]).deletion)
        let evidence = SyncDeletionSummary(id: summary.id, eventIDs: summary.eventIDs, timestampMS: summary.timestampMS, frontier: summary.frontier, observedFieldVersions: [SyncObservedField(name: "title", versionID: id(3))])
        let kept = SyncMutation(id: id(2), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: b, counter: 1, timestampMS: 2, kind: .delete, fields: [], resolvedParentVersionIDs: [id(1)], retainedDeletionEvidence: evidence)
        let future = edit(3,c,1,[id(2)])
        #expect(throws: SyncMergeError.self) { try MergeEngine.reduce(events: [kept,future]) }
    }

    @Test func resolvingAfterKeptDeletionDoesNotRevivePreviouslyDiscardedEdit() throws {
        let old = deletion(1,a)
        let e = edit(2,b)
        let initial = try #require(MergeEngine.reduce(events: [old,e]).conflicts.first)
        let kept = try initial.resolveKeepingDeletion(mutationID: id(3), deviceID: b, counter: 2, timestampMS: 2)
        let newer = edit(4,c)
        let full = try MergeEngine.reduce(events: [old,e,kept,newer])
        let conflict = try #require(full.conflicts.first)
        let resolved = try conflict.resolve(value: Data("final choice".utf8), mutationID: id(5), deviceID: c, counter: 2, timestampMS: 3)
        let result = try MergeEngine.merge(state: full.state, remote: resolved)
        #expect(result.deletion == nil)
        #expect(result.conflicts.isEmpty)
        #expect(result.fields.first?.value == Data("final choice".utf8))
    }

    @Test func allFullAndCompactedResolutionPermutationsConverge() throws {
        let old = deletion(1,a)
        let firstEdit = edit(2,b)
        let initial = try #require(MergeEngine.reduce(events: [old,firstEdit]).conflicts.first)
        let kept = try initial.resolveKeepingDeletion(mutationID: id(3), deviceID: b, counter: 2, timestampMS: 2)
        let secondEdit = edit(4,c)
        let unresolved = try #require(MergeEngine.reduce(events: [old,firstEdit,kept,secondEdit]).conflicts.first)
        let compactUnresolved = try MergeEngine.reduce(events: [kept,secondEdit])
        #expect(unresolved == compactUnresolved.conflicts.first)
        let resolved = try unresolved.resolve(value: Data("chosen".utf8), mutationID: id(5), deviceID: c, counter: 2, timestampMS: 3)
        let full = [old,firstEdit,kept,secondEdit,resolved]
        let expected = try MergeEngine.reduce(events: full)
        #expect(expected.deletion == nil)
        #expect(expected.conflicts.isEmpty)
        #expect(expected.fields.first?.value == Data("chosen".utf8))
        func permute(_ remaining: [SyncMutation], _ prefix: [SyncMutation]) throws {
            if remaining.isEmpty {
                let reduced = try MergeEngine.reduce(events: prefix)
                #expect(reduced.fields == expected.fields)
                #expect(reduced.conflicts == expected.conflicts)
                #expect(reduced.deletion == expected.deletion)
                let replay = try MergeEngine.merge(state: reduced.state, remote: resolved)
                #expect(replay.fields == expected.fields)
                #expect(replay.conflicts.isEmpty)
                return
            }
            for index in remaining.indices {
                var rest = remaining
                let next = rest.remove(at: index)
                try permute(rest, prefix + [next])
            }
        }
        try permute(full, [])
        let compact = try MergeEngine.reduce(events: [kept,secondEdit,resolved])
        #expect(compact.fields == expected.fields)
        #expect(compact.conflicts == expected.conflicts)
        #expect(compact.deletion == expected.deletion)
    }

    @Test func repeatedKeepThenEditableResolutionConvergesAcrossAllOrders() throws {
        let old = deletion(1,a)
        let firstEdit = edit(2,b)
        let initial = try #require(MergeEngine.reduce(events: [old,firstEdit]).conflicts.first)
        let firstKeep = try initial.resolveKeepingDeletion(mutationID: id(3), deviceID: b, counter: 2, timestampMS: 2)
        let secondEdit = edit(4,c)
        let secondConflict = try #require(MergeEngine.reduce(events: [old,firstEdit,firstKeep,secondEdit]).conflicts.first)
        let secondKeep = try secondConflict.resolveKeepingDeletion(mutationID: id(5), deviceID: c, counter: 2, timestampMS: 3)
        let thirdEdit = edit(6,d)
        let thirdFull = try #require(MergeEngine.reduce(events: [old,firstEdit,firstKeep,secondEdit,secondKeep,thirdEdit]).conflicts.first)
        let thirdCompact = try #require(MergeEngine.reduce(events: [secondKeep,thirdEdit]).conflicts.first)
        #expect(thirdFull == thirdCompact)
        let chosen = Data("after two keeps".utf8)
        let final = try thirdFull.resolve(value: chosen, mutationID: id(7), deviceID: d, counter: 2, timestampMS: 4)
        let history = [old,firstEdit,firstKeep,secondEdit,secondKeep,thirdEdit,final]
        func allOrders(_ rest: [SyncMutation], _ prefix: [SyncMutation]) throws {
            if rest.isEmpty {
                let result = try MergeEngine.reduce(events: prefix)
                #expect(result.conflicts.isEmpty)
                #expect(result.deletion == nil)
                #expect(result.fields.first?.value == chosen)
                return
            }
            for index in rest.indices {
                var tail = rest
                let next = tail.remove(at: index)
                try allOrders(tail, prefix + [next])
            }
        }
        try allOrders(history, [])
        let compact = try MergeEngine.reduce(events: [secondKeep,thirdEdit,final])
        #expect(compact.conflicts.isEmpty)
        #expect(compact.deletion == nil)
        #expect(compact.fields.first?.value == chosen)
    }

    @Test func conflictingHistoricalPayloadsRejectAndRollBack() async throws {
        let db = try await store()
        let repo = GoalRepository(store: db)
        try await repo.create(GoalRecord(id: entity, title: "base", detail: "detail", status: "active", createdAtMS: 1, updatedAtMS: 1), context: MutationContext(id: id(1), deviceID: a, timestamp: 1))
        let original = try #require(try await ChangeJournal(store: db).pending(limit: 10).first)
        var object = try #require(JSONSerialization.jsonObject(with: original.payload) as? [String: Any])
        var causal = try #require(object["causality"] as? [String: Any])
        var fields = try #require(causal["changedFields"] as? [[String: Any]])
        for index in fields.indices where fields[index]["fieldName"] as? String == "title" {
            fields[index]["ancestorVersionIDs"] = [id(99)]
        }
        causal["changedFields"] = fields
        object["causality"] = causal
        let altered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try await db.write { connection in
            try connection.execute(sql: "INSERT INTO outbox (id,mutation_id,entity_type,entity_id,payload,status,created_at_ms) VALUES (?,?,'goal',?,?,'pending',1)", arguments: [UUID().uuidString,id(1).lowercased(),entity,altered])
        }
        await #expect(throws: RepositoryError.self) {
            try await repo.update(GoalRecord(id: entity, title: "later", detail: "detail", status: "active", createdAtMS: 1, updatedAtMS: 2), context: MutationContext(id: id(2), deviceID: a, timestamp: 2))
        }
        #expect(try await repo.get(id: entity)?.title == "base")
        #expect(try await db.read { connection in try Int.fetchOne(connection, sql: "SELECT count(*) FROM outbox") } == 2)
    }

    @Test func retainedDeletionSurvivesDurableJournalAndCanonicalReplay() async throws {
        let db = try await store()
        let old = SyncMutation(id: id(1), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: a, counter: 8, timestampMS: 90 * 86_400_000, kind: .delete, fields: [])
        let e = edit(2,b)
        let initial = try #require(MergeEngine.reduce(events: [old,e]).conflicts.first)
        let kept = try initial.resolveKeepingDeletion(mutationID: id(3), deviceID: b, counter: 2, timestampMS: 1)
        let snapshot = try kept.journalCausality()
        let payload = try JSONSerialization.data(withJSONObject: ["id": id(3), "deviceID": b, "entityType": "goal", "entityID": entity, "timestamp": 1, "operation": "delete", "causality": JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot))], options: [.sortedKeys])
        try await db.write { connection in
            try connection.execute(sql: "INSERT INTO outbox (id,mutation_id,entity_type,entity_id,payload,status,created_at_ms) VALUES (?,?,'goal',?,?,'pending',1)", arguments: [UUID().uuidString,id(3),entity,payload])
        }
        let pending = try #require(try await ChangeJournal(store: db).pending(limit: 10).first)
        let restored = try SyncMutation(id: pending.id, entityType: pending.entityType, entityID: pending.entityID, entityVersion: 1, timestampMS: pending.createdAtMS, kind: .delete, fieldValues: [:], causality: pending.causality)
        let full = try MergeEngine.reduce(events: [old,e,kept])
        let compact = try MergeEngine.reduce(events: [restored])
        #expect(full.deletion == compact.deletion)
        let summary = try #require(compact.deletion)
        let stone = SyncTombstone(deletionVersionID: summary.id, deletedAtMS: summary.timestampMS, frontier: summary.frontier, unresolvedConflictIDs: [])
        let incomplete = [a,b].map { SyncDevice(id: $0, acknowledgedFrontier: VersionVector(entries: [DeviceCounter(deviceID: b, counter: 3)]), removedAtMS: nil, removalEventSynchronized: false) }
        #expect(!TombstonePolicy.mayPurge(stone, devices: incomplete, nowMS: 200 * 86_400_000))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let canonical = try encoder.encode(compact.state)
        #expect(try encoder.encode(JSONDecoder().decode(SyncMergeState.self, from: canonical)) == canonical)
    }
}
