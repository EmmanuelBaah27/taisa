import Foundation
import GRDB
import Testing
@testable import TaisaStorage

@Suite(.serialized) struct TaisaMigratorTests {
    @Test func migrationIsIdempotentAndCreatesAllDomainTables() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let store = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let tables = try await store.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
        }
        let expected = ["profile", "conversations", "messages", "goals", "milestones", "actions", "evidence", "memory_items", "memory_sources", "sync_devices", "field_versions", "conflicts", "outbox", "inbox_quarantine", "tombstones", "sync_state", "vault_metadata", "snapshot_manifests", "migration_state"]
        for name in expected { #expect(tables.contains(name)) }
        try await store.write { db in
            try db.execute(sql: "INSERT INTO profile (id, display_name, updated_at_ms) VALUES (?, ?, ?)", arguments: [UUID().uuidString, "preserved", 123])
        }
        let reopened = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let state = try await reopened.read { db in
            (try Int.fetchOne(db, sql: "PRAGMA user_version"), try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM profile"), try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM grdb_migrations"))
        }
        #expect(state.0 == 1)
        #expect(state.1 == 1)
        #expect(state.2 == 1)
        #expect(!tables.contains("recordings"))
    }

    @Test func interruptedMigrationRollsBackAllSchemaChanges() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let queue = try fixture.makeKeyedQueue()
        try await queue.write { db in try db.execute(sql: "CREATE TABLE goals (conflicting_column TEXT)") }
        await #expect(throws: StorageError.migrationFailed) {
            try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        }
        let state = try await queue.read { db in
            (try Int.fetchOne(db, sql: "PRAGMA user_version"), try String.fetchOne(db, sql: "SELECT name FROM sqlite_master WHERE name = 'profile'"), try String.fetchOne(db, sql: "SELECT name FROM sqlite_master WHERE name = 'goals'"))
        }
        #expect(state.0 == 0)
        #expect(state.1 == nil)
        #expect(state.2 == "goals")
    }

    @Test func futureSchemaIsRejectedWithoutMutation() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let queue = try fixture.makeKeyedQueue()
        try await queue.write { db in try db.execute(sql: "PRAGMA user_version = 99") }
        let before = try Data(contentsOf: fixture.url)
        await #expect(throws: StorageError.unsupportedSchemaVersion(99)) {
            try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        }
        #expect(try Data(contentsOf: fixture.url) == before)
    }

    @Test func oneMutationCanVersionTwoFields() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let store = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let entity = UUID().uuidString
        let device = UUID().uuidString
        let titleVersion = UUID().uuidString
        let detailVersion = UUID().uuidString
        try await store.write { db in
            try db.execute(
                sql: "INSERT INTO field_versions (id, entity_type, entity_id, field_name, version_id, device_id, device_counter, updated_at_ms) VALUES (?, 'goal', ?, 'title', ?, ?, 1, 100)",
                arguments: [UUID().uuidString, entity, titleVersion, device]
            )
            try db.execute(
                sql: "INSERT INTO field_versions (id, entity_type, entity_id, field_name, version_id, device_id, device_counter, updated_at_ms) VALUES (?, 'goal', ?, 'detail', ?, ?, 1, 100)",
                arguments: [UUID().uuidString, entity, detailVersion, device]
            )
        }
        let count = try await store.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM field_versions") }
        #expect(count == 2)
    }
}

private struct MigrationFixture {
    let directory: URL
    let url: URL
    let key = Data((0..<32).map(UInt8.init))
    let keys: FixedDatabaseKeyStore

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("migration.sqlite")
        keys = FixedDatabaseKeyStore(key: key)
    }

    func makeKeyedQueue() throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA key = \"x'000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f'\"")
        }
        return try DatabaseQueue(path: url.path, configuration: configuration)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private actor FixedDatabaseKeyStore: DatabaseKeyStore {
    let key: Data
    init(key: Data) { self.key = key }
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { Issue.record("Existing fixture key must not be replaced") }
}
