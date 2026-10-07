import Foundation
import Testing
import TaisaStorage
@testable import TaisaSync

private actor FinalKeys: DatabaseKeyStore {
    var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ value: Data) async throws { key = value }
}

@Suite(.serialized) struct FinalIndependentProbes {
    let entity = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
    let a = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    let b = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    let c = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    func id(_ n: Int) -> String { String(format: "dddddddd-dddd-4ddd-8ddd-%012d", n) }
    func edit(_ n: Int, device: String, counter: Int64, field: String = "title", parents: [String] = []) -> SyncMutation {
        SyncMutation(id:id(n),entityType:"goal",entityID:entity,entityVersion:1,deviceID:device,counter:counter,timestampMS:1,kind:.update,fields:[SyncField(name:field,value:Data("value-\(n)".utf8),versionID:id(n),ancestorVersionIDs:parents,deviceCounter:counter)])
    }
    func keptHistory(field: String) throws -> (SyncMutation, [SyncMutation]) {
        let e1 = edit(10,device:a,counter:1,field:field)
        let e2 = edit(20,device:a,counter:2,field:field,parents:[id(10)])
        let e3 = edit(30,device:a,counter:3,field:field,parents:[id(20)])
        let e4 = edit(40,device:a,counter:4,field:field,parents:[id(30)])
        let d = SyncMutation(id:id(50),entityType:"goal",entityID:entity,entityVersion:1,deviceID:b,counter:1,timestampMS:1,kind:.delete,fields:[],observedFieldVersions:[SyncObservedField(name:field,versionID:id(40))])
        let competitor = edit(60,device:c,counter:1,field:field)
        let history = [e1,e2,e3,e4,d,competitor]
        let conflict = try #require(MergeEngine.reduce(events:history).conflicts.first)
        let keep = try conflict.resolveKeepingDeletion(mutationID:id(70),deviceID:b,counter:2,timestampMS:2)
        return (keep,history)
    }

    @Test(arguments:["title","detail"])
    func compactedDeletionAcceptsStaleObservedAncestorsBeforeAnyEditResolution(field: String) throws {
        let (keep,history) = try keptHistory(field:field)
        let full = try MergeEngine.reduce(events:history + [keep])
        #expect(full.conflicts.isEmpty)
        for stale in history.prefix(4) {
            do {
                let compact = try MergeEngine.reduce(events:[keep,stale])
                #expect(compact.deletion == full.deletion)
                #expect(compact.conflicts.isEmpty)
                #expect(compact.fields.isEmpty)
            } catch { Issue.record("Known stale ancestor rejected: \(stale.counter); \(error)") }
        }
    }

    @Test(arguments:["title","detail"])
    func compactedDeletionAcceptsStaleAncestorsAlongsideNewConflict(field:String) throws {
        let (keep,history) = try keptHistory(field:field)
        let fresh = edit(80,device:c,counter:2,field:field)
        let full = try MergeEngine.reduce(events:history + [keep,fresh])
        for stale in history.prefix(4) {
            do {
                let compact = try MergeEngine.reduce(events:[keep,fresh,stale])
                #expect(compact.conflicts == full.conflicts)
                for conflict in compact.conflicts { _ = try conflict.validated() }
            } catch { Issue.record("Known stale ancestor with fresh conflict rejected: \(stale.counter); \(error)") }
        }
    }

    @Test func realEncryptedJournalPreservesMapButCannotReplayItsKnownAncestor() async throws {
        let (keep,history) = try keptHistory(field:"title")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let store = try await TaisaStore.open(at:directory.appendingPathComponent("probe.sqlite"),keyStore:FinalKeys())
        let payload = try JSONSerialization.data(withJSONObject:["id":keep.id,"deviceID":keep.deviceID,"entityType":"goal","entityID":entity,"timestamp":2,"operation":"delete","causality":JSONSerialization.jsonObject(with:JSONEncoder().encode(keep.journalCausality()))],options:[.sortedKeys])
        try await store.write { try $0.execute(sql:"INSERT INTO outbox (id,mutation_id,entity_type,entity_id,payload,status,created_at_ms) VALUES (?,?,'goal',?,?,'pending',2)",arguments:[UUID().uuidString,keep.id,entity,payload]) }
        let pending = try #require(try await ChangeJournal(store:store).pending(limit:10).first)
        let restored = try SyncMutation(id:pending.id,entityType:pending.entityType,entityID:pending.entityID,entityVersion:1,timestampMS:pending.createdAtMS,kind:.delete,fieldValues:[:],causality:pending.causality)
        #expect(restored.retainedDeletionEvidence?.fieldAncestry == keep.retainedDeletionEvidence?.fieldAncestry)
        try restored.validate()
        try history[0].validate()
        #expect(try MergeEngine.reduce(events:history + [restored]).conflicts.isEmpty)
        // The already retained E10 title is a known discarded ancestor.
        let compact = try MergeEngine.reduce(events:[restored,history[0]])
        #expect(compact.conflicts.isEmpty)
        #expect(compact.deletion != nil)
    }

    @Test func canonicalAncestryMapOrderingAndLegacyRoundtrip() throws {
        let (keep,_) = try keptHistory(field:"title")
        let evidence = try #require(keep.retainedDeletionEvidence)
        let map = try #require(evidence.fieldAncestry)
        let reversed = map.mapValues { Array($0.reversed()).map { $0.lowercased() } }
        let alternative = SyncDeletionSummary(id:evidence.id.lowercased(),eventIDs:evidence.eventIDs.map { $0.lowercased() },timestampMS:evidence.timestampMS,frontier:evidence.frontier,observedFieldVersions:evidence.observedFieldVersions,fieldAncestry:reversed)
        #expect(try evidence.validated() == alternative.validated())
        let restored = try SyncMutation(id:keep.id,entityType:keep.entityType,entityID:keep.entityID,entityVersion:1,timestampMS:keep.timestampMS,kind:.delete,fieldValues:[:],causality:keep.journalCausality())
        #expect(try MergeEngine.reduce(events:[keep]).state == MergeEngine.reduce(events:[restored]).state)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(MergeEngine.reduce(events:[keep]).state)
        #expect(try encoder.encode(JSONDecoder().decode(SyncMergeState.self,from:bytes)) == bytes)
    }

    @Test(arguments: ["title", "detail"])
    func newConcurrentEditsAndUnknownAncestorsStillCompete(field: String) throws {
        let (keep,_) = try keptHistory(field:field)
        let newEdits = [
            edit(80,device:c,counter:2,field:field),
            edit(90,device:c,counter:2,field:field,parents:[id(20)]),
            edit(100,device:c,counter:2,field:field,parents:[id(999)])
        ]
        for fresh in newEdits {
            let result = try MergeEngine.reduce(events:[keep,fresh])
            #expect(result.deletion != nil)
            #expect(result.fields.isEmpty)
            #expect(result.conflicts.count == 1)
            let conflict = try #require(result.conflicts.first)
            #expect(conflict.fieldName == field)
            let editBranch = conflict.first.value != nil ? conflict.first : conflict.second
            #expect(editBranch.versionID == fresh.id.uppercased())
            #expect(editBranch.value == fresh.fields.first?.value)
            _ = try conflict.validated()
        }
    }

    @Test(arguments: ["title", "detail"])
    func knownAncestorInOneFieldDoesNotHideTheOtherField(field: String) throws {
        let other = field == "title" ? "detail" : "title"
        let original = SyncMutation(id:id(10),entityType:"goal",entityID:entity,entityVersion:1,deviceID:a,counter:1,timestampMS:1,kind:.update,fields:[
            SyncField(name:field,value:Data("known".utf8),versionID:id(10),deviceCounter:1),
            SyncField(name:other,value:Data("unobserved".utf8),versionID:id(10),deviceCounter:1)])
        let middle = edit(20,device:a,counter:2,field:field,parents:[id(10)])
        let observed = edit(40,device:a,counter:3,field:field,parents:[id(20)])
        let removal = SyncMutation(id:id(50),entityType:"goal",entityID:entity,entityVersion:1,deviceID:b,counter:1,timestampMS:1,kind:.delete,fields:[],observedFieldVersions:[SyncObservedField(name:field,versionID:id(40))])
        let fresh = edit(60,device:c,counter:1,field:field)
        let history = [original,middle,observed,removal,fresh]
        let initial = try #require(MergeEngine.reduce(events:history).conflicts.first { $0.fieldName == field })
        let keep = try initial.resolveKeepingDeletion(mutationID:id(70),deviceID:b,counter:2,timestampMS:2)
        let result = try MergeEngine.reduce(events:[keep,original])
        #expect(result.deletion != nil)
        #expect(result.conflicts.count == 1)
        let conflict = try #require(result.conflicts.first)
        #expect(conflict.fieldName == other)
        #expect((conflict.first.value ?? conflict.second.value) == Data("unobserved".utf8))
        _ = try conflict.validated()
    }

    @Test(arguments: ["title", "detail"])
    func encryptedJournalStaleAndConcurrentReplayPreservesTombstoneAndConflict(field: String) async throws {
        let (keep,history) = try keptHistory(field:field)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let store = try await TaisaStore.open(at:directory.appendingPathComponent("exception.sqlite"),keyStore:FinalKeys())
        let payload = try JSONSerialization.data(withJSONObject:["id":keep.id,"deviceID":keep.deviceID,"entityType":"goal","entityID":entity,"timestamp":2,"operation":"delete","causality":JSONSerialization.jsonObject(with:JSONEncoder().encode(keep.journalCausality()))],options:[.sortedKeys])
        try await store.write { try $0.execute(sql:"INSERT INTO outbox (id,mutation_id,entity_type,entity_id,payload,status,created_at_ms) VALUES (?,?,'goal',?,?,'pending',2)",arguments:[UUID().uuidString,keep.id,entity,payload]) }
        let pending = try #require(try await ChangeJournal(store:store).pending(limit:10).first)
        let restored = try SyncMutation(id:pending.id,entityType:pending.entityType,entityID:pending.entityID,entityVersion:1,timestampMS:pending.createdAtMS,kind:.delete,fieldValues:[:],causality:pending.causality)
        let fresh = edit(80,device:c,counter:2,field:field)
        let full = try MergeEngine.reduce(events:history + [keep])
        let fullConcurrent = try MergeEngine.reduce(events:history + [keep,fresh])
        #expect(fullConcurrent.conflicts.count == 1)
        let persistence = ConflictStore(store:store)
        for stale in history.prefix(4) {
            let compact = try MergeEngine.reduce(events:[restored,stale])
            #expect(compact.deletion == full.deletion)
            #expect(compact.conflicts.isEmpty)
            #expect(compact.fields.isEmpty)
            let concurrent = try MergeEngine.reduce(events:[restored,fresh,stale])
            #expect(concurrent.deletion == fullConcurrent.deletion)
            #expect(concurrent.conflicts == fullConcurrent.conflicts)
            for conflict in concurrent.conflicts {
                _ = try conflict.validated()
                try await persistence.persist(conflict,at:3)
            }
        }
        #expect(try await persistence.unresolved() == fullConcurrent.conflicts)
    }
}
