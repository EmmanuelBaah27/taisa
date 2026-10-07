import Foundation
import Testing
import TaisaStorage
@testable import TaisaSync

private actor R4Keys: DatabaseKeyStore {
    var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ value: Data) async throws { key = value }
}

@Suite(.serialized) struct Round4IndependentProbes {
    let entity = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
    let a = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    let b = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    let c = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    func id(_ n: Int) -> String { String(format: "dddddddd-dddd-4ddd-8ddd-%012d", n) }
    func edit(_ n: Int, _ device: String, _ counter: Int64 = 1, _ parents: [String] = [], name: String = "title") -> SyncMutation {
        SyncMutation(id: id(n), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: device, counter: counter, timestampMS: 1, kind: .update, fields: [SyncField(name: name, value: Data("value-\(n)".utf8), versionID: id(n), ancestorVersionIDs: parents, deviceCounter: counter)])
    }
    func store() async throws -> TaisaStore {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return try await TaisaStore.open(at: path.appendingPathComponent("probe.sqlite"), keyStore: R4Keys())
    }
    func blob(_ db: TaisaStore) async throws -> Data {
        try await db.read { try Data.fetchOne($0, sql: "SELECT local_value FROM conflicts")! }
    }

    @Test func equivalentPoorerAndResolvedReplayPreserveStoredBytes() async throws {
        let db = try await store()
        let original = try #require(MergeEngine.reduce(events: [edit(30,a,3,[id(20),id(10)]),edit(40,b)]).conflicts.first)
        let reordered = try #require(MergeEngine.reduce(events: [edit(30,a,3,[id(10),id(20)]),edit(40,b)]).conflicts.first)
        let poorer = try #require(MergeEngine.reduce(events: [edit(30,a,3,[id(20)]),edit(40,b)]).conflicts.first)
        let richer = try #require(MergeEngine.reduce(events: [edit(30,a,3,[id(20),id(10),id(5)]),edit(40,b)]).conflicts.first)
        let conflicts = ConflictStore(store: db)
        try await conflicts.persist(original, at: 1)
        let bytes = try await blob(db)
        for replay in [original,reordered,poorer] {
            try await conflicts.persist(replay, at: 2)
            #expect(try await blob(db) == bytes)
        }
        let resolution = try reordered.resolve(value: Data("choice".utf8), mutationID: id(50), deviceID: b, counter: 2, timestampMS: 3)
        try await db.write { try ConflictStore.resolve(reordered, using: resolution, at: 3, in: $0) }
        for replay in [poorer,reordered,original] {
            try await conflicts.persist(replay, at: 4)
            #expect(try await blob(db) == bytes)
        }
        await #expect(throws: SyncMergeError.alreadyResolved) { try await conflicts.persist(richer, at: 5) }
        #expect(try await blob(db) == bytes)
        #expect(try await conflicts.unresolved().isEmpty)
    }

    @Test func independentlyArrivingAncestryUnionCanResolveInEitherOrder() async throws {
        let x = try #require(MergeEngine.reduce(events: [edit(30,a,3,[id(20)]),edit(40,b)]).conflicts.first)
        let y = try #require(MergeEngine.reduce(events: [edit(30,a,3,[id(10)]),edit(40,b)]).conflicts.first)
        let union = try #require(MergeEngine.reduce(events: [edit(30,a,3,[id(20),id(10)]),edit(40,b)]).conflicts.first)
        for order in [[x,y],[y,x]] {
            let db = try await store()
            let conflicts = ConflictStore(store: db)
            for part in order { try await conflicts.persist(part, at: 1) }
            let actual = try #require(try await conflicts.unresolved().first)
            #expect(Set(actual.first.ancestorVersionIDs) == Set(union.first.ancestorVersionIDs))
            let resolution = try union.resolve(value: Data("choice".utf8), mutationID: id(50), deviceID: b, counter: 2, timestampMS: 3)
            try await db.write { try ConflictStore.resolve(union, using: resolution, at: 3, in: $0) }
            for part in order { try await conflicts.persist(part, at: 4) }
            #expect(try await conflicts.unresolved().isEmpty)
        }
    }

    @Test func observedDetailAncestryDoesNotInvalidateUnobservedTitleConflict() async throws {
        let base = SyncMutation(id: id(10), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: a, counter: 1, timestampMS: 1, kind: .update, fields: [
            SyncField(name: "title", value: Data("title".utf8), versionID: id(10), ancestorVersionIDs: [], deviceCounter: 1),
            SyncField(name: "detail", value: Data("detail".utf8), versionID: id(10), ancestorVersionIDs: [], deviceCounter: 1)])
        let detail = edit(20,b,1,[id(10)],name:"detail")
        let deletion = SyncMutation(id: id(30), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: c, counter: 1, timestampMS: 1, kind: .delete, fields: [], observedFieldVersions: [SyncObservedField(name:"detail",versionID:id(20))])
        let result = try MergeEngine.reduce(events: [base,detail,deletion])
        #expect(result.conflicts.count == 1)
        let conflict = try #require(result.conflicts.first)
        #expect(conflict.fieldName == "title")
        let deleted = conflict.first.value == nil ? conflict.first : conflict.second
        #expect(!deleted.ancestorVersionIDs.contains(id(10).uppercased()))
        let db = try await store()
        try await ConflictStore(store: db).persist(conflict, at: 1)
        let keep = try conflict.resolveKeepingDeletion(mutationID: id(40), deviceID: c, counter: 2, timestampMS: 2)
        #expect(try MergeEngine.reduce(events:[base,detail,deletion,keep]).conflicts.isEmpty)
    }

    @Test func sparseObservedLineageSurvivesDurableOutboxAndRepeatedResolution() async throws {
        let oldest = edit(1,a)
        let middle = edit(2,a,2,[id(1)])
        let observed = edit(3,a,3,[id(2)])
        let deletion = SyncMutation(id: id(4), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: b, counter: 1, timestampMS: 1, kind: .delete, fields: [], observedFieldVersions: [SyncObservedField(name:"title",versionID:id(3))])
        let competing = edit(5,c)
        let conflict = try #require(MergeEngine.reduce(events:[oldest,middle,observed,deletion,competing]).conflicts.first)
        let keep = try conflict.resolveKeepingDeletion(mutationID: id(6), deviceID: c, counter: 2, timestampMS: 2)
        let db = try await store()
        let payload = try JSONSerialization.data(withJSONObject: ["id": keep.id, "deviceID": c, "entityType": "goal", "entityID": entity, "timestamp": 2, "operation": "delete", "causality": JSONSerialization.jsonObject(with: JSONEncoder().encode(keep.journalCausality()))], options:[.sortedKeys])
        try await db.write { try $0.execute(sql:"INSERT INTO outbox (id,mutation_id,entity_type,entity_id,payload,status,created_at_ms) VALUES (?,?,'goal',?,?,'pending',2)",arguments:[UUID().uuidString,keep.id,entity,payload]) }
        let pending = try #require(try await ChangeJournal(store: db).pending(limit: 10).first)
        let restored = try SyncMutation(id: pending.id, entityType: pending.entityType, entityID: pending.entityID, entityVersion: 1, timestampMS: pending.createdAtMS, kind:.delete,fieldValues:[:],causality:pending.causality)
        let later = edit(7,b,2)
        let second = try #require(MergeEngine.reduce(events:[restored,later]).conflicts.first)
        let secondKeep = try second.resolveKeepingDeletion(mutationID: id(8), deviceID:b,counter:3,timestampMS:3)
        let latest = edit(9,a,4)
        let lastConflict = try #require(MergeEngine.reduce(events:[secondKeep,latest]).conflicts.first)
        let choice = Data("final".utf8)
        let resolved = try lastConflict.resolve(value:choice,mutationID:id(10),deviceID:a,counter:5,timestampMS:4)
        let full = try MergeEngine.reduce(events:[oldest,middle,observed,deletion,competing,keep,later,secondKeep,latest,resolved])
        #expect(full.conflicts.isEmpty)
        for stale in [oldest,middle,observed] {
            let compact = try MergeEngine.reduce(events:[secondKeep,latest,resolved,stale])
            #expect(compact.conflicts.isEmpty)
            #expect(compact.fields == full.fields)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let bytes = try encoder.encode(compact.state)
            let state = try JSONDecoder().decode(SyncMergeState.self,from:bytes)
            #expect(try encoder.encode(state) == bytes)
            #expect(try MergeEngine.merge(state:state,remote:stale).fields == full.fields)
        }
    }
}
