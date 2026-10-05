import Foundation
import Testing
import TaisaStorage
import TaisaSync

private actor ConflictTestKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ value: Data) async throws { key = value }
}

@Suite(.serialized) struct ConflictStoreTests {
    private enum IntentionalRollback: Error { case stop }

    @Test func resolutionCanJoinCallerTransactionAndRollBackAtomically() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("conflicts.sqlite"), keyStore: ConflictTestKeys())
        let conflict = SyncConflict(entityType: "goal", entityID: "11111111-1111-4111-8111-111111111111", fieldName: "title", first: ConflictingValue(versionID: "00000000-0000-4000-8000-000000000001", ancestorVersionIDs: [], value: Data("A".utf8)), second: ConflictingValue(versionID: "00000000-0000-4000-8000-000000000002", ancestorVersionIDs: [], value: Data("B".utf8)))
        let repository = ConflictStore(store: store)
        try await repository.persist(conflict, at: 1)
        let resolution = try conflict.resolve(value: Data("A".utf8), mutationID: "00000000-0000-4000-8000-000000000003", deviceID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", counter: 1, timestampMS: 2)
        await #expect(throws: IntentionalRollback.self) {
            try await store.write { db in
                try ConflictStore.resolve(conflict, using: resolution, at: 2, in: db)
                throw IntentionalRollback.stop
            } as Void
        }
        #expect(try await repository.unresolved().count == 1)
        try await store.write { db in try ConflictStore.resolve(conflict, using: resolution, at: 2, in: db) }
        #expect(try await repository.unresolved().isEmpty)
    }

    @Test func decodedConflictColumnsAndAlternativesMustAgree() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("conflicts.sqlite"), keyStore: ConflictTestKeys())
        let first = ConflictingValue(versionID: "00000000-0000-4000-8000-000000000001", ancestorVersionIDs: [], value: Data("A".utf8))
        let second = ConflictingValue(versionID: "00000000-0000-4000-8000-000000000002", ancestorVersionIDs: [], value: Data("B".utf8))
        let encodedFirst = try JSONEncoder().encode(first)
        let encodedSecond = try JSONEncoder().encode(second)
        try await store.write { db in
            try db.execute(sql: "INSERT INTO conflicts (id, entity_type, entity_id, field_name, local_version_id, remote_version_id, local_value, remote_value, created_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", arguments: [UUID().uuidString, "goal", "11111111-1111-4111-8111-111111111111", "title", second.versionID, first.versionID, encodedFirst, encodedSecond, 1])
        }
        await #expect(throws: SyncMergeError.self) { try await ConflictStore(store: store).unresolved() }
    }

    @Test func nextRepositoryEditRetainsDurableResolvedBranches() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("conflicts.sqlite"), keyStore: ConflictTestKeys())
        let entity = "11111111-1111-4111-8111-111111111111"
        let device = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let base = "00000000-0000-4000-8000-000000000001"
        let a = "00000000-0000-4000-8000-000000000002"
        let b = "00000000-0000-4000-8000-000000000003"
        let resolvedID = "00000000-0000-4000-8000-000000000004"
        let nextID = "00000000-0000-4000-8000-000000000005"
        let repository = GoalRepository(store: store)
        try await repository.create(GoalRecord(id: entity, title: "Base", detail: "Detail", status: "active", createdAtMS: 1, updatedAtMS: 1), context: MutationContext(id: base, deviceID: device, timestamp: 1))
        let conflict = SyncConflict(entityType: "goal", entityID: entity, fieldName: "title", first: ConflictingValue(versionID: a, ancestorVersionIDs: [base], value: Data("A".utf8)), second: ConflictingValue(versionID: b, ancestorVersionIDs: [base], value: Data("B".utf8)))
        try await ConflictStore(store: store).persist(conflict, at: 2)
        let resolution = try conflict.resolve(value: Data("Chosen".utf8), mutationID: resolvedID, deviceID: device, counter: 2, timestampMS: 3)
        let snapshot = try resolution.journalCausality()
        let causalJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot))
        let payload = try JSONSerialization.data(withJSONObject: ["id": resolvedID, "deviceID": device, "entityType": "goal", "entityID": entity, "timestamp": 3, "operation": "update", "causality": causalJSON], options: [.sortedKeys])
        try await store.write { db in
            try ConflictStore.resolve(conflict, using: resolution, at: 3, in: db)
            try db.execute(sql: "UPDATE goals SET title = 'Chosen', updated_at_ms = 3 WHERE id = ?", arguments: [entity])
            for field in ["title", "__record"] {
                try db.execute(sql: "INSERT INTO field_versions (id, entity_type, entity_id, field_name, version_id, parent_version_id, device_id, device_counter, updated_at_ms) VALUES (?, 'goal', ?, ?, ?, ?, ?, 2, 3)", arguments: [UUID().uuidString, entity, field, resolvedID, field == "title" ? a : base, device])
            }
            try db.execute(sql: "INSERT INTO outbox (id, mutation_id, entity_type, entity_id, payload, status, created_at_ms) VALUES (?, ?, 'goal', ?, ?, 'pending', 3)", arguments: [UUID().uuidString, resolvedID, entity, payload])
        }
        try await repository.update(GoalRecord(id: entity, title: "Later", detail: "Detail", status: "active", createdAtMS: 1, updatedAtMS: 4), context: MutationContext(id: nextID, deviceID: device, timestamp: 4))
        let pending = try await ChangeJournal(store: store).pending(limit: 10)
        let next = try #require(pending.first { UUID(uuidString: $0.id) == UUID(uuidString: nextID) })
        let title = try #require(next.causality.changedFields.first { $0.fieldName == "title" })
        #expect(Set(title.ancestorVersionIDs) == Set([resolvedID, a, b, base]))
    }
    @Test func unresolvedConflictPersistsEncryptedAcrossReopenAndReplayIsIdempotent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("conflicts.sqlite")
        let keys = ConflictTestKeys()
        let store = try await TaisaStore.open(at: url, keyStore: keys)
        let conflict = SyncConflict(
            entityType: "goal", entityID: "11111111-1111-4111-8111-111111111111", fieldName: "title",
            first: ConflictingValue(versionID: "00000000-0000-4000-8000-000000000001", ancestorVersionIDs: [], value: Data("PRIVATE-CANARY-LEFT".utf8)),
            second: ConflictingValue(versionID: "00000000-0000-4000-8000-000000000002", ancestorVersionIDs: [], value: Data("PRIVATE-CANARY-RIGHT".utf8))
        )
        let conflicts = ConflictStore(store: store)
        try await conflicts.persist(conflict, at: 100)
        for _ in 0..<100 { try await conflicts.persist(conflict, at: 100) }
        let reopened = ConflictStore(store: try await TaisaStore.open(at: url, keyStore: keys))
        #expect(try await reopened.unresolved() == [conflict])
        for suffix in ["", "-wal"] {
            let file = URL(fileURLWithPath: url.path + suffix)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            let raw = try Data(contentsOf: file)
            #expect(!raw.contains(Data("PRIVATE-CANARY-LEFT".utf8)))
            #expect(!raw.contains(Data("PRIVATE-CANARY-RIGHT".utf8)))
        }
    }

    @Test func conflictingReplayFailsClosedWithoutLeakingValues() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("conflicts.sqlite"), keyStore: ConflictTestKeys())
        let saved = SyncConflict(entityType: "goal", entityID: "11111111-1111-4111-8111-111111111111", fieldName: "title", first: ConflictingValue(versionID: "00000000-0000-4000-8000-000000000001", ancestorVersionIDs: [], value: Data("PRIVATE-A".utf8)), second: ConflictingValue(versionID: "00000000-0000-4000-8000-000000000002", ancestorVersionIDs: [], value: Data("PRIVATE-B".utf8)))
        let changed = SyncConflict(entityType: saved.entityType, entityID: saved.entityID, fieldName: saved.fieldName, first: ConflictingValue(versionID: saved.first.versionID, ancestorVersionIDs: [], value: Data("PRIVATE-CHANGED".utf8)), second: saved.second)
        let conflicts = ConflictStore(store: store)
        try await conflicts.persist(saved, at: 100)
        do { try await conflicts.persist(changed, at: 100); Issue.record("changed replay accepted") }
        catch { #expect(!String(describing: error).contains("PRIVATE-CHANGED")) }
        #expect(try await conflicts.unresolved() == [saved])
    }
}
