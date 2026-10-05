import Foundation
import Testing
import TaisaStorage
@testable import TaisaSync

private actor R5Keys: DatabaseKeyStore {
    var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ value: Data) async throws { key = value }
}

@Suite(.serialized) struct Round5FieldIsolationTests {
    let entity = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
    let a = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    let b = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    let c = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    func id(_ n: Int) -> String { String(format: "dddddddd-dddd-4ddd-8ddd-%012d", n) }
    func other(_ field: String) -> String { field == "title" ? "detail" : "title" }
    func base() -> SyncMutation {
        SyncMutation(id: id(10), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: a, counter: 1, timestampMS: 1, kind: .update, fields: [
            SyncField(name: "title", value: Data("base-title".utf8), versionID: id(10), deviceCounter: 1),
            SyncField(name: "detail", value: Data("base-detail".utf8), versionID: id(10), deviceCounter: 1)])
    }
    func edit(_ n: Int, _ field: String, _ counter: Int64, parents: [String] = []) -> SyncMutation {
        SyncMutation(id: id(n), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: b, counter: counter, timestampMS: 1, kind: .update,
            fields: [SyncField(name: field, value: Data("value-\(n)".utf8), versionID: id(n), ancestorVersionIDs: parents, deviceCounter: counter)])
    }
    func deletion(_ observed: [SyncObservedField], recordParent: String? = nil) -> SyncMutation {
        SyncMutation(id: id(50), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: c, counter: 1, timestampMS: 1, kind: .delete,
            fields: [], observedFieldVersions: observed, recordParentVersionID: recordParent)
    }
    func store() async throws -> TaisaStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try await TaisaStore.open(at: directory.appendingPathComponent("round5.sqlite"), keyStore: R5Keys())
    }
    func deleted(_ conflict: SyncConflict) -> ConflictingValue { conflict.first.value == nil ? conflict.first : conflict.second }

    @Test(arguments: ["title", "detail"])
    func directOtherFieldObservationAndRecordParentDoNotGrantFieldAuthority(field: String) async throws {
        let original = base()
        let removal = deletion([SyncObservedField(name: other(field), versionID: id(10))], recordParent: id(10))
        let decision = try MergeEngine.reduce(events: [original,removal])
        #expect(decision.conflicts.count == 1)
        let conflict = try #require(decision.conflicts.first)
        #expect(conflict.fieldName == field)
        #expect(deleted(conflict).ancestorVersionIDs.isEmpty)
        _ = try conflict.validated()
        let db = try await store()
        let persistence = ConflictStore(store: db)
        try await persistence.persist(conflict, at: 1)
        let keep = try conflict.resolveKeepingDeletion(mutationID: id(70), deviceID: c, counter: 2, timestampMS: 2)
        try await db.write { try ConflictStore.resolve(conflict, using: keep, at: 2, in: $0) }
        #expect(try MergeEngine.reduce(events: [original,removal,keep]).conflicts.isEmpty)
        try await persistence.persist(conflict, at: 3)
        #expect(try await persistence.unresolved().isEmpty)
    }

    @Test(arguments: ["title", "detail"])
    func multiGenerationOtherFieldHistoryStaysSeparateAcrossPersistResolveAndCompaction(field: String) async throws {
        let original = base()
        let unrelatedField = other(field)
        let middle = edit(20,unrelatedField,1,parents:[id(10)])
        let later = edit(30,unrelatedField,2,parents:[id(20)])
        let observed = edit(40,unrelatedField,3,parents:[id(30)])
        let removal = deletion([SyncObservedField(name: unrelatedField, versionID: id(40))])
        let fullHistory = [original,middle,later,observed,removal]
        let conflict = try #require(MergeEngine.reduce(events: fullHistory).conflicts.first)
        #expect(conflict.fieldName == field)
        #expect(deleted(conflict).ancestorVersionIDs.isEmpty)
        #expect(deleted(conflict).deletionEvidence?.observedFieldVersions == [SyncObservedField(name: unrelatedField, versionID: id(40).uppercased())])
        _ = try conflict.validated()
        let db = try await store()
        let persistence = ConflictStore(store: db)
        try await persistence.persist(conflict, at: 1)
        let kept = try conflict.resolveKeepingDeletion(mutationID: id(70), deviceID: c, counter: 2, timestampMS: 2)
        try await db.write { try ConflictStore.resolve(conflict, using: kept, at: 2, in: $0) }
        let restored = try SyncMutation(id: kept.id, entityType: kept.entityType, entityID: kept.entityID, entityVersion: 1, timestampMS: kept.timestampMS, kind: .delete, fieldValues: [:], causality: kept.journalCausality())
        let fresh = edit(80,field,4)
        let fullBefore = try MergeEngine.reduce(events: fullHistory + [kept,fresh])
        let compactBefore = try MergeEngine.reduce(events: [restored,fresh])
        #expect(fullBefore.conflicts == compactBefore.conflicts)
        let second = try #require(compactBefore.conflicts.first)
        _ = try second.validated()
        try await persistence.persist(second, at: 3)
        let chosen = Data("final".utf8)
        let resolution = try second.resolve(value: chosen, mutationID: id(90), deviceID: c, counter: 3, timestampMS: 4)
        try await db.write { try ConflictStore.resolve(second, using: resolution, at: 4, in: $0) }
        try await persistence.persist(second, at: 5)
        #expect(try await persistence.unresolved().isEmpty)
        let full = try MergeEngine.reduce(events: fullHistory + [kept,fresh,resolution])
        let compact = try MergeEngine.reduce(events: [restored,fresh,resolution,original])
        #expect(full.conflicts.isEmpty)
        #expect(compact.conflicts.isEmpty)
        #expect(full.fields.first { $0.name == field }?.value == chosen)
        #expect(compact.fields.first { $0.name == field }?.value == chosen)
        #expect(full.fields.first { $0.name == unrelatedField }?.value == Data("value-40".utf8))
    }

    @Test(arguments: ["title", "detail"])
    func oneFieldKeepDoesNotPoisonRemainingFieldConflict(field: String) async throws {
        let original = base()
        let removal = deletion([])
        let initial = try MergeEngine.reduce(events: [original,removal])
        #expect(Set(initial.conflicts.map(\.fieldName)) == Set(["title","detail"]))
        let chosenConflict = try #require(initial.conflicts.first { $0.fieldName == field })
        let kept = try chosenConflict.resolveKeepingDeletion(mutationID: id(70), deviceID: c, counter: 2, timestampMS: 2)
        let full = try MergeEngine.reduce(events: [original,removal,kept])
        let compact = try MergeEngine.reduce(events: [original,kept])
        #expect(full.conflicts == compact.conflicts)
        #expect(full.conflicts.count == 1)
        let remaining = try #require(full.conflicts.first)
        #expect(remaining.fieldName == other(field))
        #expect(!deleted(remaining).ancestorVersionIDs.contains(id(10).uppercased()))
        let db = try await store()
        let persistence = ConflictStore(store: db)
        for conflict in initial.conflicts { try await persistence.persist(conflict, at: 1) }
        try await db.write { try ConflictStore.resolve(chosenConflict, using: kept, at: 2, in: $0) }
        _ = try remaining.validated()
        try await persistence.persist(remaining, at: 3)
        let finalKeep = try remaining.resolveKeepingDeletion(mutationID: id(90), deviceID: c, counter: 3, timestampMS: 4)
        try await db.write { try ConflictStore.resolve(remaining, using: finalKeep, at: 4, in: $0) }
        #expect(try await persistence.unresolved().isEmpty)
        #expect(try MergeEngine.reduce(events: [original,removal,kept,finalKeep]).conflicts.isEmpty)
    }

    @Test(arguments: ["title", "detail"])
    func fieldLineageSurvivesAnInterveningOtherFieldKeep(field: String) async throws {
        let original = base()
        let middle = edit(20,field,1,parents:[id(10)])
        let later = edit(30,field,2,parents:[id(20)])
        let observed = edit(40,field,3,parents:[id(30)])
        let competitor = SyncMutation(id: id(60), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: a, counter: 2, timestampMS: 1, kind: .update,
            fields: [SyncField(name: field, value: Data("competitor".utf8), versionID: id(60), deviceCounter: 2)])
        let removal = deletion([SyncObservedField(name: field,versionID: id(40))])
        let history = [original,middle,later,observed,competitor,removal]
        let title = try #require(MergeEngine.reduce(events: history).conflicts.first { $0.fieldName == field })
        let firstKeep = try title.resolveKeepingDeletion(mutationID: id(70), deviceID: c, counter: 2, timestampMS: 2)
        let detail = try #require(MergeEngine.reduce(events: history + [firstKeep]).conflicts.first { $0.fieldName == other(field) })
        _ = try detail.validated()
        let secondKeep = try detail.resolveKeepingDeletion(mutationID: id(90), deviceID: c, counter: 3, timestampMS: 3)
        let db = try await store()
        let payload = try JSONSerialization.data(withJSONObject: ["id":secondKeep.id,"deviceID":c,"entityType":"goal","entityID":entity,"timestamp":3,"operation":"delete","causality":JSONSerialization.jsonObject(with:JSONEncoder().encode(secondKeep.journalCausality()))],options:[.sortedKeys])
        try await db.write { try $0.execute(sql:"INSERT INTO outbox (id,mutation_id,entity_type,entity_id,payload,status,created_at_ms) VALUES (?,?,'goal',?,?,'pending',3)",arguments:[UUID().uuidString,secondKeep.id,entity,payload]) }
        let pending = try #require(try await ChangeJournal(store:db).pending(limit:10).first)
        let restored = try SyncMutation(id:pending.id,entityType:pending.entityType,entityID:pending.entityID,entityVersion:1,timestampMS:pending.createdAtMS,kind:.delete,fieldValues:[:],causality:pending.causality)
        let titleAncestors = Set(restored.retainedDeletionEvidence?.fieldAncestry?[field] ?? [])
        #expect(titleAncestors.isSuperset(of:[id(10).uppercased(),id(20).uppercased(),id(30).uppercased()]))
        let fresh = edit(100,field,4)
        let last = try #require(MergeEngine.reduce(events: [restored,fresh]).conflicts.first)
        try await ConflictStore(store:db).persist(last,at:4)
        let chosen = Data("final".utf8)
        let resolution = try last.resolve(value: chosen, mutationID: id(110), deviceID: a, counter: 3, timestampMS: 4)
        try await db.write { try ConflictStore.resolve(last,using:resolution,at:5,in:$0) }
        try await ConflictStore(store:db).persist(last,at:6)
        #expect(try await ConflictStore(store:db).unresolved().isEmpty)
        for stale in [original,middle,later,observed] {
            let result = try MergeEngine.reduce(events: [restored,fresh,resolution,stale])
            #expect(result.conflicts.isEmpty)
            #expect(result.fields.first { $0.name == field }?.value == chosen)
        }
    }

    @Test func learnedFieldAncestryEnrichesAndPoorerReplayPreservesBytes() async throws {
        let original = base()
        let middle = edit(20,"title",1,parents:[id(10)])
        let observed = edit(40,"title",2,parents:[id(20)])
        let removal = deletion([SyncObservedField(name:"title",versionID:id(40))])
        let fresh = edit(80,"title",3)
        let poorer = try #require(MergeEngine.reduce(events:[removal,fresh]).conflicts.first)
        let richer = try #require(MergeEngine.reduce(events:[original,middle,observed,removal,fresh]).conflicts.first { $0.fieldName == "title" })
        let db = try await store()
        let persistence = ConflictStore(store:db)
        try await persistence.persist(poorer,at:1)
        try await persistence.persist(richer,at:2)
        #expect(try await persistence.unresolved() == [richer])
        let bytes = try await db.read { try Data.fetchOne($0,sql:"SELECT local_value FROM conflicts WHERE field_name = 'title'") }
        for replay in [poorer,richer] {
            try await persistence.persist(replay,at:3)
            #expect(try await db.read { try Data.fetchOne($0,sql:"SELECT local_value FROM conflicts WHERE field_name = 'title'") } == bytes)
        }
        let resolution = try richer.resolve(value:Data("chosen".utf8),mutationID:id(90),deviceID:c,counter:2,timestampMS:4)
        try await db.write { try ConflictStore.resolve(richer,using:resolution,at:4,in:$0) }
        for replay in [poorer,richer] {
            try await persistence.persist(replay,at:5)
            #expect(try await db.read { try Data.fetchOne($0,sql:"SELECT local_value FROM conflicts WHERE field_name = 'title'") } == bytes)
        }
    }

    @Test func repositoryNextEditUsesOnlyItsRetainedFieldAncestry() async throws {
        let db = try await store()
        let repo = GoalRepository(store: db)
        try await repo.create(GoalRecord(id: entity, title: "base", detail: "detail", status: "active", createdAtMS: 1, updatedAtMS: 1), context: MutationContext(id: id(10), deviceID: a, timestamp: 1))
        let evidence = SyncDeletionSummary(id: id(50), eventIDs: [id(50)], timestampMS: 1, frontier: VersionVector(entries: [DeviceCounter(deviceID: c,counter: 1)]), observedFieldVersions: [], fieldAncestry: ["title":[id(20)],"detail":[id(30)]])
        let keep = SyncMutation(id: id(70), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: c, counter: 2, timestampMS: 2, kind: .delete, fields: [], recordParentVersionID: id(50), resolvedParentVersionIDs: [id(50),id(20)], retainedDeletionEvidence: evidence)
        let payload = try JSONSerialization.data(withJSONObject: ["id":keep.id,"deviceID":c,"entityType":"goal","entityID":entity,"timestamp":2,"operation":"delete","causality":JSONSerialization.jsonObject(with: JSONEncoder().encode(keep.journalCausality()))], options:[.sortedKeys])
        try await db.write { connection in
            try connection.execute(sql:"INSERT INTO outbox (id,mutation_id,entity_type,entity_id,payload,status,created_at_ms) VALUES (?,?,'goal',?,?,'pending',2)",arguments:[UUID().uuidString,keep.id,entity,payload])
            // Emulate the coordinator's supplied field frontier after restoring
            // readable domain state; Task 6 owns domain/tombstone application.
            try connection.execute(sql:"INSERT INTO field_versions (id,entity_type,entity_id,field_name,version_id,parent_version_id,device_id,device_counter,updated_at_ms) VALUES (?,'goal',?,'title',?,NULL,?,2,2)",arguments:[UUID().uuidString,entity,keep.id,c])
        }
        let saved = try #require(try await ChangeJournal(store:db).pending(limit:10).first { UUID(uuidString:$0.id) == UUID(uuidString:keep.id) })
        #expect(saved.causality.retainedDeletionCausality?.fieldAncestry == ["title":[id(20).uppercased()],"detail":[id(30).uppercased()]])
        try await repo.update(GoalRecord(id:entity,title:"next",detail:"detail",status:"active",createdAtMS:1,updatedAtMS:3),context:MutationContext(id:id(90),deviceID:b,timestamp:3))
        let next = try #require(try await ChangeJournal(store:db).pending(limit:10).first { UUID(uuidString:$0.id) == UUID(uuidString:id(90)) })
        let title = try #require(next.causality.changedFields.first { $0.fieldName == "title" })
        #expect(title.ancestorVersionIDs == [id(70).uppercased(),id(20).uppercased()])
        #expect(!title.ancestorVersionIDs.contains(id(30).uppercased()))
    }

    @Test func legacyRetainedDeletionMapIsOptionalAndMalformedMapsFailWithoutPrivateDetails() throws {
        let legacy = Data("{\"versionIDs\":[\"\(id(50))\"],\"latestDeletedAtMS\":1,\"frontier\":[{\"deviceID\":\"\(c)\",\"counter\":1}],\"observedFieldVersions\":[]}".utf8)
        let decoded = try JSONDecoder().decode(RetainedDeletionCausality.self,from:legacy)
        #expect(decoded.fieldAncestry == nil)
        let empty = SyncDeletionSummary(id:id(50),eventIDs:[id(50)],timestampMS:1,frontier:VersionVector(entries:[DeviceCounter(deviceID:c,counter:1)]),observedFieldVersions:[],fieldAncestry:[:])
        #expect(try empty.validated().fieldAncestry == nil)
        #expect(!(try JSONSerialization.jsonObject(with:JSONEncoder().encode(decoded)) as! [String:Any]).keys.contains("fieldAncestry"))
        for malformed in [ ["title":["PRIVATE-CANARY"]], ["title":[id(20),id(20).uppercased()]], ["__record":[id(20)]], ["title":[]] ] {
            let summary = SyncDeletionSummary(id:id(50),eventIDs:[id(50)],timestampMS:1,frontier:VersionVector(entries:[DeviceCounter(deviceID:c,counter:1)]),observedFieldVersions:[],fieldAncestry:malformed)
            do {
                _ = try summary.validated()
                Issue.record("Malformed retained field ancestry was accepted")
            } catch {
                #expect(error as? SyncMergeError == .malformedMutation)
                #expect(!String(describing:error).contains("PRIVATE-CANARY"))
            }
        }
    }

    @Test func partialFieldResolutionConflictsOnlyWithUnresolvedDeletionVersions() async throws {
        let original = base()
        let first = deletion([])
        let second = SyncMutation(id:id(60),entityType:"goal",entityID:entity,entityVersion:1,deviceID:b,counter:1,timestampMS:1,kind:.delete,fields:[])
        let partial = SyncMutation(id:id(70),entityType:"goal",entityID:entity,entityVersion:1,deviceID:a,counter:2,timestampMS:2,kind:.resolve,fields:[
            SyncField(name:"title",value:Data("title".utf8),versionID:id(70),ancestorVersionIDs:[id(50),id(10)],deviceCounter:2),
            SyncField(name:"detail",value:Data("detail".utf8),versionID:id(70),ancestorVersionIDs:[id(10),id(30)],deviceCounter:2)])
        let result = try MergeEngine.reduce(events:[original,first,second,partial])
        #expect(result.deletion != nil)
        #expect(result.conflicts.count == 2)
        let title = try #require(result.conflicts.first { $0.fieldName == "title" })
        #expect(deleted(title).versionID == id(60).uppercased())
        let db = try await store()
        for conflict in result.conflicts {
            _ = try conflict.validated()
            try await ConflictStore(store:db).persist(conflict,at:3)
        }
    }
}
