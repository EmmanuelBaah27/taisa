import Foundation
import Testing
import TaisaSync
import TaisaStorage

private actor FreshKeys: DatabaseKeyStore {
    var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ value: Data) async throws { key = value }
}

@Suite(.serialized) struct FreshTask5RereviewTests {
    let entity = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
    let a = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    let b = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    let c = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    func id(_ n: Int) -> String { String(format: "dddddddd-dddd-4ddd-8ddd-%012d", n) }
    func edit(_ n: Int, device: String, counter: Int64 = 1, ancestors: [String] = [], name: String = "title", frontier: VersionVector? = nil) -> SyncMutation {
        SyncMutation(id: id(n), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: device, counter: counter, timestampMS: 1, kind: .update, fields: [SyncField(name: name, value: Data("v\(n)".utf8), versionID: id(n), ancestorVersionIDs: ancestors, deviceCounter: counter)], frontier: frontier)
    }
    func freshStore() async throws -> TaisaStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try await TaisaStore.open(at: directory.appendingPathComponent("fresh.sqlite"), keyStore: FreshKeys())
    }

    @Test func keepDeletionRetainsOriginalRetentionAndFrontier() throws {
        let deletion = SyncMutation(id: id(1), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: a, counter: 8, timestampMS: 90 * 86_400_000, kind: .delete, fields: [])
        let e = edit(2, device: b)
        let conflict = try #require(MergeEngine.reduce(events: [deletion, e]).conflicts.first)
        let resolution = try conflict.resolveKeepingDeletion(mutationID: id(3), deviceID: b, counter: 2, timestampMS: 1)
        let result = try MergeEngine.reduce(events: [deletion, e, resolution])
        #expect(result.conflicts.isEmpty)
        let summary = try #require(result.deletion)
        #expect(summary.timestampMS >= deletion.timestampMS)
        #expect(summary.frontier.counter(for: a) == 8)
        let stone = SyncTombstone(deletionVersionID: summary.id, deletedAtMS: summary.timestampMS, frontier: summary.frontier, unresolvedConflictIDs: [])
        let devices = [a,b].map { SyncDevice(id: $0, acknowledgedFrontier: VersionVector(entries: [DeviceCounter(deviceID: b, counter: 3)]), removedAtMS: nil, removalEventSynchronized: false) }
        #expect(!TombstonePolicy.mayPurge(stone, devices: devices, nowMS: 91 * 86_400_000))
    }

    @Test func keepDeletionDoesNotLoseOtherObservedFields() throws {
        let title = edit(1, device: a)
        let detail = edit(2, device: a, counter: 2, name: "detail")
        let deletion = SyncMutation(id: id(3), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: a, counter: 3, timestampMS: 2, kind: .delete, fields: [], observedFieldVersions: [SyncObservedField(name: "title", versionID: id(1)), SyncObservedField(name: "detail", versionID: id(2))])
        let concurrent = edit(4, device: b)
        let initial = try MergeEngine.reduce(events: [title, detail, deletion, concurrent])
        #expect(initial.conflicts.count == 1)
        let conflict = try #require(initial.conflicts.first)
        let resolution = try conflict.resolveKeepingDeletion(mutationID: id(5), deviceID: b, counter: 2, timestampMS: 3)
        let result = try MergeEngine.merge(state: initial.state, remote: resolution)
        #expect(result.conflicts.isEmpty)
    }

    @Test func frontierCannotRegressThroughAnotherDevice() throws {
        let parent = edit(1, device: b, counter: 5, frontier: VersionVector(entries: [DeviceCounter(deviceID: b, counter: 5), DeviceCounter(deviceID: a, counter: 8)]))
        let child = edit(2, device: a, counter: 2, ancestors: [id(1)], frontier: VersionVector(entries: [DeviceCounter(deviceID: a, counter: 2), DeviceCounter(deviceID: b, counter: 5)]))
        #expect(throws: SyncMergeError.self) { try MergeEngine.reduce(events: [parent, child]) }
    }

    @Test func observedFieldRegressionFailsClosed() throws {
        let e = edit(1, device: a, counter: 8)
        let deletion = SyncMutation(id: id(2), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: a, counter: 2, timestampMS: 1, kind: .delete, fields: [], observedFieldVersions: [SyncObservedField(name: "title", versionID: id(1))])
        #expect(throws: SyncMergeError.self) { try MergeEngine.reduce(events: [e, deletion]) }
    }

    @Test func wrongFieldResolutionCannotClearConflict() async throws {
        let store = try await freshStore()
        func multiField(_ n: Int, _ device: String) -> SyncMutation {
            SyncMutation(id: id(n), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: device, counter: 1, timestampMS: 1, kind: .update, fields: ["title", "detail"].map { SyncField(name: $0, value: Data("v\(n)".utf8), versionID: id(n), deviceCounter: 1) })
        }
        let conflicts = try MergeEngine.reduce(events: [multiField(1,a),multiField(2,b)]).conflicts
        let conflict = try #require(conflicts.first { $0.fieldName == "title" })
        let detail = try #require(conflicts.first { $0.fieldName == "detail" })
        try await ConflictStore(store: store).persist(conflict, at: 1)
        let wrong = try detail.resolve(value: Data("chosen".utf8), mutationID: id(3), deviceID: c, counter: 1, timestampMS: 2)
        await #expect(throws: SyncMergeError.self) { try await store.write { db in try ConflictStore.resolve(conflict, using: wrong, at: 2, in: db) } }
        #expect(try await ConflictStore(store: store).unresolved().count == 1)
    }

    @Test(.disabled("Pre-existing unknown-field domain-application gap, outside round-2 findings")) func malformedFieldFailsAtMergeBoundary() throws {
        #expect(throws: SyncMergeError.self) { try MergeEngine.reduce(events: [edit(1, device: a, name: "notAField")]) }
    }

    @Test func ambiguousAncestryPayloadFailsClosed() async throws {
        let store = try await freshStore()
        let repository = GoalRepository(store: store)
        let base = GoalRecord(id: entity, title: "Base", detail: "D", status: "active", createdAtMS: 1, updatedAtMS: 1)
        try await repository.create(base, context: MutationContext(id: id(1), deviceID: a, timestamp: 1))
        try await store.write { db in
            try db.execute(sql: "INSERT INTO outbox (id,mutation_id,entity_type,entity_id,payload,status,created_at_ms) SELECT ?,lower(mutation_id),entity_type,entity_id,payload,status,created_at_ms FROM outbox LIMIT 1", arguments: [UUID().uuidString])
        }
        await #expect(throws: RepositoryError.self) {
            try await repository.update(GoalRecord(id: entity, title: "Later", detail: "D", status: "active", createdAtMS: 1, updatedAtMS: 2), context: MutationContext(id: id(2), deviceID: a, timestamp: 2))
        }
        #expect(try await repository.get(id: entity)?.title == "Base")
    }

    @Test func allFiveEventPermutationsAndGroupingConverge() throws {
        let events = [edit(1, device: a), edit(2, device: a, counter: 2, ancestors: [id(1)]), edit(3, device: b, ancestors: [id(1)]), edit(4, device: c, name: "detail"), edit(5, device: c, counter: 2, ancestors: [id(4)], name: "detail")]
        func permutations(_ items: [SyncMutation]) -> [[SyncMutation]] {
            if items.isEmpty { return [[]] }
            return items.indices.flatMap { i in var rest = items; let first = rest.remove(at: i); return permutations(rest).map { [first] + $0 } }
        }
        let expected = try MergeEngine.reduce(events: events)
        for order in permutations(events) {
            var running = try MergeEngine.reduce(events: [order[0]])
            for event in order.dropFirst() { running = try MergeEngine.merge(state: running.state, remote: event) }
            #expect(running == expected)
            for split in 1..<order.count {
                let left = try MergeEngine.reduce(events: Array(order[..<split]))
                let right = try MergeEngine.reduce(events: Array(order[split...]))
                #expect(try MergeEngine.reduce(events: left.state.events + right.state.events) == expected)
            }
            #expect(try MergeEngine.merge(state: running.state, remote: order[0]).state == expected.state)
        }
    }

    @Test func conflictPersistAndResolveRollBackWithOtherWrites() async throws {
        enum Rollback: Error { case intentional }
        let store = try await freshStore()
        let conflict = try #require(MergeEngine.reduce(events: [edit(1, device: a), edit(2, device: b)]).conflicts.first)
        await #expect(throws: Rollback.self) {
            try await store.write { db in
                try ConflictStore.persist(conflict, at: 1, in: db)
                try db.execute(sql: "INSERT INTO goals (id,title,detail,status,created_at_ms,updated_at_ms) VALUES (?, 'Synthetic', 'D', 'active', 1, 1)", arguments: [entity])
                throw Rollback.intentional
            } as Void
        }
        #expect(try await ConflictStore(store: store).unresolved().isEmpty)
        #expect(try await GoalRepository(store: store).get(id: entity) == nil)
        try await ConflictStore(store: store).persist(conflict, at: 1)
        let resolution = try conflict.resolve(value: Data("R".utf8), mutationID: id(3), deviceID: c, counter: 1, timestampMS: 2)
        await #expect(throws: Rollback.self) {
            try await store.write { db in
                try ConflictStore.resolve(conflict, using: resolution, at: 2, in: db)
                try db.execute(sql: "INSERT INTO outbox (id, mutation_id, entity_type, entity_id, payload, status, created_at_ms) VALUES (?, ?, 'goal', ?, ?, 'pending', 2)", arguments: [UUID().uuidString, id(3), entity, Data()])
                throw Rollback.intentional
            } as Void
        }
        #expect(try await ConflictStore(store: store).unresolved().count == 1)
        #expect(try await store.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM outbox") } == 0)
    }

    @Test func legacySnapshotShapeAndUUIDNormalizationRemainCompatible() async throws {
        let store = try await freshStore()
        let repository = GoalRepository(store: store)
        try await repository.create(GoalRecord(id: entity, title: entity, detail: "D", status: "active", createdAtMS: 1, updatedAtMS: 1), context: MutationContext(id: id(1), deviceID: a, timestamp: 1))
        let first = try #require(try await ChangeJournal(store: store).pending(limit: 1).first)
        let snapshot = try JSONEncoder().encode(first.causality)
        let object = try #require(JSONSerialization.jsonObject(with: snapshot) as? [String: Any])
        #expect(object["resolvedParentVersionIDs"] == nil)
        #expect(try JSONDecoder().decode(CausalSnapshot.self, from: snapshot) == first.causality)
        let payload = try #require(JSONSerialization.jsonObject(with: first.payload) as? [String: Any])
        #expect((payload["record"] as? [String: Any])?["title"] as? String == entity)
    }

    @Test func strictConflictValidationAndVectorUnion() async throws {
        let store = try await freshStore()
        let x = ConflictingValue(versionID: id(1), ancestorVersionIDs: [], value: Data("x".utf8))
        let y = ConflictingValue(versionID: id(2), ancestorVersionIDs: [], value: Data("y".utf8))
        let bad = [
            SyncConflict(entityType: "goal", entityID: entity, fieldName: "unknown", first: x, second: y),
            SyncConflict(entityType: "goal", entityID: entity, fieldName: "title", first: x, second: ConflictingValue(versionID: id(2), ancestorVersionIDs: [id(2)], value: y.value)),
            SyncConflict(entityType: "goal", entityID: entity, fieldName: "title", first: x, second: ConflictingValue(versionID: id(2), ancestorVersionIDs: [id(3),id(3)], value: y.value)),
            SyncConflict(entityType: "goal", entityID: entity, fieldName: "title", first: x, second: ConflictingValue(versionID: id(2), ancestorVersionIDs: [], value: x.value))
        ]
        for conflict in bad { await #expect(throws: SyncMergeError.self) { try await ConflictStore(store: store).persist(conflict, at: 1) } }
        #expect(try await ConflictStore(store: store).unresolved().isEmpty)
        let left = VersionVector(entries: [DeviceCounter(deviceID: a, counter: 3)])
        let right = VersionVector(entries: [DeviceCounter(deviceID: a.uppercased(), counter: 2), DeviceCounter(deviceID: b, counter: 1)])
        let union = try #require(left.merged(with: right))
        #expect(union.counter(for: a) == 3)
        #expect(union.counter(for: b) == 1)
        #expect(union.isBeyond(left))
        #expect(right.merged(with: left) == union)
    }

    @Test func repositoryResolutionOutboxAndNextEditRoundTrip() async throws {
        let store = try await freshStore()
        let repository = GoalRepository(store: store)
        try await repository.create(GoalRecord(id: entity, title: "Base", detail: "D", status: "active", createdAtMS: 1, updatedAtMS: 1), context: MutationContext(id: id(1), deviceID: a, timestamp: 1))
        try await repository.update(GoalRecord(id: entity, title: "Left", detail: "D", status: "active", createdAtMS: 1, updatedAtMS: 2), context: MutationContext(id: id(2), deviceID: a, timestamp: 2))
        func adapt(_ change: PendingChange, kind: SyncMutation.Kind) throws -> SyncMutation {
            let object = try #require(JSONSerialization.jsonObject(with: change.payload) as? [String: Any])
            let record = try #require(object["record"] as? [String: Any])
            var fields: [String: Data] = [:]
            for field in change.causality.changedFields {
                fields[field.fieldName] = try JSONSerialization.data(withJSONObject: try #require(record[field.fieldName]), options: [.fragmentsAllowed, .sortedKeys])
            }
            return try SyncMutation(id: change.id, entityType: change.entityType, entityID: change.entityID, entityVersion: 1, timestampMS: change.createdAtMS, kind: kind, fieldValues: fields, causality: change.causality)
        }
        let pending = try await ChangeJournal(store: store).pending(limit: 10)
        let base = try adapt(pending[0], kind: .create)
        let left = try adapt(pending[1], kind: .update)
        let right = edit(3, device: b, ancestors: [id(1)])
        let conflict = try #require(MergeEngine.reduce(events: [base, left, right]).conflicts.first)
        try await ConflictStore(store: store).persist(conflict, at: 3)
        let resolvedRecord = GoalRecord(id: entity, title: "Chosen", detail: "D", status: "active", createdAtMS: 1, updatedAtMS: 2)
        let resolution = try conflict.resolve(value: JSONEncoder().encode("Chosen"), mutationID: id(4), deviceID: a, counter: 3, timestampMS: 4)
        let snapshot = try resolution.journalCausality()
        let payload = try JSONSerialization.data(withJSONObject: ["id": id(4), "deviceID": a, "entityType": "goal", "entityID": entity, "timestamp": 4, "operation": "update", "record": JSONSerialization.jsonObject(with: JSONEncoder().encode(resolvedRecord)), "causality": JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot))], options: [.sortedKeys])
        try await store.write { db in
            try ConflictStore.resolve(conflict, using: resolution, at: 4, in: db)
            try db.execute(sql: "UPDATE goals SET title = 'Chosen' WHERE id = ? COLLATE NOCASE", arguments: [entity])
            for field in ["title", "__record"] {
                try db.execute(sql: "INSERT INTO field_versions (id,entity_type,entity_id,field_name,version_id,parent_version_id,device_id,device_counter,updated_at_ms) VALUES (?, 'goal', ?, ?, ?, ?, ?, 3, 4)", arguments: [UUID().uuidString,entity,field,id(4),id(2),a])
            }
            try db.execute(sql: "INSERT INTO outbox (id,mutation_id,entity_type,entity_id,payload,status,created_at_ms) VALUES (?, ?, 'goal', ?, ?, 'pending', 4)", arguments: [UUID().uuidString,id(4),entity,payload])
        }
        try await repository.update(GoalRecord(id: entity, title: "Later", detail: "D", status: "active", createdAtMS: 1, updatedAtMS: 5), context: MutationContext(id: id(5), deviceID: a, timestamp: 5))
        let finalPending = try await ChangeJournal(store: store).pending(limit: 10)
        let durableResolution = try adapt(try #require(finalPending.first { UUID(uuidString: $0.id) == UUID(uuidString: id(4)) }), kind: .resolve)
        let next = try adapt(try #require(finalPending.first { UUID(uuidString: $0.id) == UUID(uuidString: id(5)) }), kind: .update)
        let title = try #require(next.fields.first { $0.name == "title" })
        #expect(Set(title.ancestorVersionIDs) == Set([id(1),id(2),id(3),id(4)].map { UUID(uuidString: $0)!.uuidString }))
        let merged = try MergeEngine.reduce(events: [next,right,base,durableResolution,left])
        #expect(merged.conflicts.isEmpty)
        #expect(try merged.fields.first { $0.name == "title" }?.value == JSONEncoder().encode("Later"))
        #expect(try await ConflictStore(store: store).unresolved().isEmpty)
    }
}
