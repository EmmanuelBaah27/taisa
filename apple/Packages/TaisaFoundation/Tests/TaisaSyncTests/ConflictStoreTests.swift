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
