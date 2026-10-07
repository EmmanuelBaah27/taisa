import Foundation
import Testing
import TaisaStorage
@testable import TaisaSync

private actor R3Keys: DatabaseKeyStore {
    var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ value: Data) async throws { key = value }
}

@Suite(.serialized) struct Round3ReviewProbes {
    let entity = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
    let a = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    let b = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    let c = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    let d = "99999999-9999-4999-8999-999999999999"
    func id(_ n: Int) -> String { String(format: "dddddddd-dddd-4ddd-8ddd-%012d", n) }
    func edit(_ n: Int, _ device: String, _ counter: Int64 = 1, _ parents: [String] = []) -> SyncMutation {
        SyncMutation(id: id(n), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: device, counter: counter, timestampMS: 1, kind: .update, fields: [SyncField(name: "title", value: Data("value-\(n)".utf8), versionID: id(n), ancestorVersionIDs: parents, deviceCounter: counter)])
    }
    func deletion(_ n: Int, _ device: String, _ counter: Int64 = 1, observed: [SyncObservedField] = []) -> SyncMutation {
        SyncMutation(id: id(n), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: device, counter: counter, timestampMS: 1, kind: .delete, fields: [], observedFieldVersions: observed)
    }
    func store() async throws -> TaisaStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try await TaisaStore.open(at: directory.appendingPathComponent("probe.sqlite"), keyStore: R3Keys())
    }

    @Test func exactConflictReplayDoesNotChangeAncestryOrBlockResolution() async throws {
        let db = try await store()
        let original = edit(10, a)
        let parent = edit(20, a, 2, [id(10)])
        let left = edit(30, a, 3, [id(20), id(10)])
        let right = edit(40, b)
        let conflict = try #require(MergeEngine.reduce(events: [original,parent,left,right]).conflicts.first)
        let conflicts = ConflictStore(store: db)
        try await conflicts.persist(conflict, at: 1)
        try await conflicts.persist(conflict, at: 2)
        #expect(try await conflicts.unresolved() == [conflict])
        let resolution = try conflict.resolve(value: Data("chosen".utf8), mutationID: id(50), deviceID: b, counter: 2, timestampMS: 3)
        try await db.write { connection in
            try ConflictStore.resolve(conflict, using: resolution, at: 3, in: connection)
        }
        #expect(try await conflicts.unresolved().isEmpty)
        try await conflicts.persist(conflict, at: 4)
    }

    @Test func resolvedConflictExactReplayRemainsIdempotent() async throws {
        let db = try await store()
        let left = edit(30, a, 3, [id(20), id(10)])
        let right = edit(40, b)
        let conflict = try #require(MergeEngine.reduce(events: [left,right]).conflicts.first)
        let conflicts = ConflictStore(store: db)
        try await conflicts.persist(conflict, at: 1)
        let resolution = try conflict.resolve(value: Data("chosen".utf8), mutationID: id(50), deviceID: b, counter: 2, timestampMS: 3)
        try await db.write { connection in try ConflictStore.resolve(conflict, using: resolution, at: 3, in: connection) }
        try await conflicts.persist(conflict, at: 4)
        #expect(try await conflicts.unresolved().isEmpty)
    }

    @Test func observedEditAncestrySurvivesCompactedDeletionResolution() throws {
        let ancestor = edit(10,a)
        let oldEdit = edit(20,a,2,[id(10)])
        let deleted = deletion(30,b,observed: [SyncObservedField(name: "title", versionID: id(20))])
        let competing = edit(40,c)
        let first = try #require(MergeEngine.reduce(events: [ancestor,oldEdit,deleted,competing]).conflicts.first)
        let kept = try first.resolveKeepingDeletion(mutationID: id(50), deviceID: c, counter: 2, timestampMS: 2)
        let latest = edit(60,d)
        let fullBefore = try MergeEngine.reduce(events: [ancestor,oldEdit,deleted,competing,kept,latest])
        let compactBefore = try MergeEngine.reduce(events: [kept,latest])
        #expect(fullBefore.conflicts == compactBefore.conflicts)
        let second = try #require(compactBefore.conflicts.first)
        let chosen = Data("final".utf8)
        let resolved = try second.resolve(value: chosen, mutationID: id(70), deviceID: d, counter: 2, timestampMS: 3)
        let full = try MergeEngine.reduce(events: [ancestor,oldEdit,deleted,competing,kept,latest,resolved])
        let replay = try MergeEngine.reduce(events: [kept,latest,resolved,ancestor])
        #expect(full.conflicts.isEmpty)
        #expect(replay.conflicts.isEmpty)
        #expect(replay.fields == full.fields)
    }

    @Test func threeGenerationObservedEditSurvivesJournalAndRepeatedKeeps() throws {
        let oldest = edit(5,a)
        let middle = edit(10,a,2,[id(5)])
        let observed = edit(20,a,3,[id(10),id(5)])
        let deleted = deletion(30,b,observed: [SyncObservedField(name: "title", versionID: id(20))])
        let competitor = edit(40,c)
        let first = try #require(MergeEngine.reduce(events: [oldest,middle,observed,deleted,competitor]).conflicts.first)
        let firstKeep = try first.resolveKeepingDeletion(mutationID: id(50), deviceID: c, counter: 2, timestampMS: 2)
        #expect(Set(firstKeep.resolvedParentVersionIDs ?? []).contains(id(5).uppercased()))
        let snapshot = try firstKeep.journalCausality()
        let restored = try SyncMutation(id: firstKeep.id, entityType: firstKeep.entityType, entityID: firstKeep.entityID, entityVersion: 1, timestampMS: firstKeep.timestampMS, kind: .delete, fieldValues: [:], causality: snapshot)
        let later = edit(60,d)
        let second = try #require(MergeEngine.reduce(events: [restored,later]).conflicts.first)
        let secondKeep = try second.resolveKeepingDeletion(mutationID: id(70), deviceID: d, counter: 2, timestampMS: 3)
        let latest = edit(80,b,2)
        let third = try #require(MergeEngine.reduce(events: [secondKeep,latest]).conflicts.first)
        let chosen = Data("final".utf8)
        let resolution = try third.resolve(value: chosen, mutationID: id(90), deviceID: b, counter: 3, timestampMS: 4)
        let full = try MergeEngine.reduce(events: [oldest,middle,observed,deleted,competitor,firstKeep,later,secondKeep,latest,resolution])
        let compact = try MergeEngine.reduce(events: [secondKeep,latest,resolution,oldest])
        #expect(full.conflicts.isEmpty)
        #expect(compact.conflicts.isEmpty)
        #expect(compact.fields == full.fields)
        #expect(compact.fields.first?.value == chosen)
    }

    @Test func richerEvidenceAfterResolutionReturnsTypedStateWithoutReopening() async throws {
        let db = try await store()
        let first = deletion(1,a)
        let changed = edit(2,b)
        let conflict = try #require(MergeEngine.reduce(events: [first,changed]).conflicts.first)
        let conflicts = ConflictStore(store: db)
        try await conflicts.persist(conflict, at: 1)
        let resolution = try conflict.resolve(value: Data("chosen".utf8), mutationID: id(4), deviceID: b, counter: 2, timestampMS: 2)
        try await db.write { try ConflictStore.resolve(conflict, using: resolution, at: 2, in: $0) }
        let richer = try #require(MergeEngine.reduce(events: [first,changed,deletion(3,c)]).conflicts.first)
        await #expect(throws: SyncMergeError.alreadyResolved) { try await conflicts.persist(richer, at: 3) }
        try await conflicts.persist(conflict, at: 4)
        #expect(try await conflicts.unresolved().isEmpty)
    }

    @Test func nearestFirstAncestryEnrichmentCanResolveWithoutReloadAndReplay() async throws {
        let db = try await store()
        let poorer = try #require(MergeEngine.reduce(events: [edit(30,a,3,[id(20)]),edit(40,b)]).conflicts.first)
        let richer = try #require(MergeEngine.reduce(events: [edit(30,a,3,[id(20),id(10),id(5)]),edit(40,b)]).conflicts.first)
        let conflicts = ConflictStore(store: db)
        try await conflicts.persist(poorer, at: 1)
        try await conflicts.persist(richer, at: 2)
        try await conflicts.persist(poorer, at: 3)
        try await conflicts.persist(richer, at: 4)
        #expect(try await conflicts.unresolved() == [richer])
        let resolution = try richer.resolve(value: Data("chosen".utf8), mutationID: id(50), deviceID: b, counter: 2, timestampMS: 5)
        try await db.write { try ConflictStore.resolve(richer, using: resolution, at: 5, in: $0) }
        try await conflicts.persist(poorer, at: 6)
        try await conflicts.persist(richer, at: 7)
        #expect(try await conflicts.unresolved().isEmpty)
        #expect(try await db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM conflicts") } == 1)
    }

    @Test func sparseObservedAncestrySurvivesCompactionAndEveryStaleAncestor() throws {
        let oldest = edit(5,a)
        let middle = edit(10,a,2,[id(5)])
        let observed = edit(20,a,3,[id(10)])
        let deleted = deletion(30,b,observed: [SyncObservedField(name: "title", versionID: id(20))])
        let competitor = edit(40,c)
        let first = try #require(MergeEngine.reduce(events: [oldest,middle,observed,deleted,competitor]).conflicts.first)
        let kept = try first.resolveKeepingDeletion(mutationID: id(50), deviceID: c, counter: 2, timestampMS: 2)
        #expect(Set(kept.resolvedParentVersionIDs ?? []).isSuperset(of: [id(5).uppercased(),id(10).uppercased(),id(20).uppercased()]))
        let restored = try SyncMutation(id: kept.id, entityType: kept.entityType, entityID: kept.entityID, entityVersion: 1, timestampMS: kept.timestampMS, kind: .delete, fieldValues: [:], causality: kept.journalCausality())
        let latest = edit(60,d)
        let conflict = try #require(MergeEngine.reduce(events: [restored,latest]).conflicts.first)
        let chosen = Data("final".utf8)
        let resolved = try conflict.resolve(value: chosen, mutationID: id(70), deviceID: d, counter: 2, timestampMS: 3)
        for stale in [oldest,middle,observed] {
            let replay = try MergeEngine.reduce(events: [restored,latest,resolved,stale])
            #expect(replay.conflicts.isEmpty)
            #expect(replay.fields.count == 1)
            #expect(replay.fields.first?.value == chosen)
        }
    }

    @Test func equivalentAncestorOrderIsReplayAndCanResolveWithoutReload() async throws {
        let db = try await store()
        let original = try #require(MergeEngine.reduce(events: [edit(30,a,3,[id(20),id(10)]),edit(40,b)]).conflicts.first)
        let reordered = try #require(MergeEngine.reduce(events: [edit(30,a,3,[id(10),id(20)]),edit(40,b)]).conflicts.first)
        let conflicts = ConflictStore(store: db)
        try await conflicts.persist(original, at: 1)
        try await conflicts.persist(reordered, at: 2)
        #expect(try await conflicts.unresolved() == [original])
        let resolution = try reordered.resolve(value: Data("chosen".utf8), mutationID: id(50), deviceID: b, counter: 2, timestampMS: 3)
        try await db.write { try ConflictStore.resolve(reordered, using: resolution, at: 3, in: $0) }
        try await conflicts.persist(reordered, at: 4)
        try await conflicts.persist(original, at: 5)
        #expect(try await conflicts.unresolved().isEmpty)
    }

    @Test func observedFieldAncestryDoesNotTreatRecordOrderingAsOverwriteAuthority() throws {
        let base = edit(10,a)
        let competing = edit(20,b)
        let observed = SyncMutation(id: id(30), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: c, counter: 1, timestampMS: 1, kind: .update,
            fields: [SyncField(name: "title", value: Data("observed".utf8), versionID: id(30), ancestorVersionIDs: [id(10)], deviceCounter: 1)], recordParentVersionID: id(20))
        let deleted = deletion(40,a,2,observed: [SyncObservedField(name: "title", versionID: id(30))])
        let decision = try MergeEngine.reduce(events: [base,competing,observed,deleted])
        let conflict = try #require(decision.conflicts.first)
        let deletionBranch = conflict.first.value == nil ? conflict.first : conflict.second
        #expect(deletionBranch.ancestorVersionIDs.contains(id(10).uppercased()))
        #expect(!deletionBranch.ancestorVersionIDs.contains(id(20).uppercased()))
        let kept = try conflict.resolveKeepingDeletion(mutationID: id(50), deviceID: a, counter: 3, timestampMS: 2)
        #expect(try MergeEngine.reduce(events: [base,competing,observed,deleted,kept]).conflicts.isEmpty)
    }

    @Test func evidenceEnrichmentRollsBackWithAdjacentWrite() async throws {
        let db = try await store()
        let first = deletion(1,a)
        let e = edit(2,b)
        let initial = try #require(MergeEngine.reduce(events: [first,e]).conflicts.first)
        let richer = try #require(MergeEngine.reduce(events: [first,e,deletion(3,c)]).conflicts.first)
        let conflicts = ConflictStore(store: db)
        try await conflicts.persist(initial, at: 1)
        enum Rollback: Error { case expected }
        await #expect(throws: Rollback.self) {
            try await db.write { connection in
                try ConflictStore.persist(richer, at: 2, in: connection)
                try connection.execute(sql: "UPDATE conflicts SET created_at_ms = 99")
                throw Rollback.expected
            }
        }
        #expect(try await conflicts.unresolved() == [initial])
        #expect(try await db.read { try Int.fetchOne($0, sql: "SELECT created_at_ms FROM conflicts") } == 1)
    }

    @Test func legacyMissingDeletionEvidenceEnrichesAndPoorerReplayPreservesIt() async throws {
        let db = try await store()
        let full = try #require(MergeEngine.reduce(events: [deletion(1,a),edit(2,b)]).conflicts.first)
        let legacy = SyncConflict(entityType: full.entityType, entityID: full.entityID, fieldName: full.fieldName,
          first: ConflictingValue(versionID: full.first.versionID, ancestorVersionIDs: full.first.ancestorVersionIDs, value: full.first.value),
          second: ConflictingValue(versionID: full.second.versionID, ancestorVersionIDs: full.second.ancestorVersionIDs, value: full.second.value))
        let conflicts = ConflictStore(store: db)
        try await conflicts.persist(legacy, at: 1)
        try await conflicts.persist(full, at: 2)
        try await conflicts.persist(legacy, at: 3)
        #expect(try await conflicts.unresolved() == [full])
    }
}
