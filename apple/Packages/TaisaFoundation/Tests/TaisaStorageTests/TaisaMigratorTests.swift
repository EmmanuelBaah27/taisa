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
        let expected = ["profile", "conversations", "messages", "goals", "milestones", "actions", "evidence", "memory_items", "memory_sources", "sync_devices", "field_versions", "conflicts", "outbox", "inbox_quarantine", "tombstones", "sync_state", "vault_metadata", "snapshot_manifests", "migration_state", "voice_turns", "audio_cleanup_queue", "conversation_drafts", "message_revisions"]
        for name in expected { #expect(tables.contains(name)) }
        try await store.write { db in
            try db.execute(sql: "INSERT INTO profile (id, display_name, updated_at_ms) VALUES (?, ?, ?)", arguments: [UUID().uuidString, "preserved", 123])
        }
        let reopened = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let state = try await reopened.read { db in
            (try Int.fetchOne(db, sql: "PRAGMA user_version"), try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM profile"), try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM grdb_migrations"))
        }
        #expect(state.0 == 3)
        #expect(state.1 == 1)
        #expect(state.2 == 3)
        #expect(!tables.contains("recordings"))
    }

    @Test func interruptedMigrationRollsBackAllSchemaChanges() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let queue = try fixture.makeKeyedQueue()
        #expect(throws: StorageError.migrationFailed) {
            try TaisaMigrator.migrate(queue, from: 0) { db in
                try TaisaSchema.createVersion1(in: db)
                throw MigrationInterruption.injected
            }
        }
        let state = try await queue.read { db in
            (try Int.fetchOne(db, sql: "PRAGMA user_version"), try String.fetchOne(db, sql: "SELECT name FROM sqlite_master WHERE name = 'profile'"), try String.fetchOne(db, sql: "SELECT name FROM sqlite_master WHERE name = 'goals'"))
        }
        #expect(state.0 == 0)
        #expect(state.1 == nil)
        #expect(state.2 == nil)
    }

    @Test func existingVersionOneStoreMigratesForwardWithoutLosingData() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let queue = try fixture.makeKeyedQueue()
        var legacy = DatabaseMigrator()
        legacy.registerMigration("v1", foreignKeyChecks: .immediate) { db in
            try TaisaSchema.createVersion1(in: db)
            try db.execute(
                sql: "INSERT INTO migration_state (version, applied_at_ms) VALUES (1, 1)"
            )
            try db.execute(sql: "PRAGMA user_version = 1")
        }
        try legacy.migrate(queue)
        try await queue.write { db in
            try db.execute(
                sql: "INSERT INTO profile (id, display_name, updated_at_ms) VALUES (?, 'preserved-v1', 1)",
                arguments: ["00000000-0000-0000-0000-000000000401"]
            )
        }
        try queue.close()

        let store = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let state = try await store.read { db in
            (
                try Int.fetchOne(db, sql: "PRAGMA user_version"),
                try String.fetchOne(db, sql: "SELECT display_name FROM profile"),
                try db.tableExists("voice_turns"),
                try Int.fetchAll(db, sql: "SELECT version FROM migration_state ORDER BY version")
            )
        }
        #expect(state.0 == 3)
        #expect(state.1 == "preserved-v1")
        #expect(state.2)
        #expect(state.3 == [1, 2, 3])
    }

    @Test func existingVersionTwoStoreMigratesWithoutInventingDraftsOrRevisions() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let queue = try fixture.makeKeyedQueue()
        var legacy = DatabaseMigrator()
        legacy.registerMigration("v1", foreignKeyChecks: .immediate) { db in
            try TaisaSchema.createVersion1(in: db)
            try db.execute(sql: "INSERT INTO migration_state (version, applied_at_ms) VALUES (1, 1)")
            try db.execute(sql: "PRAGMA user_version = 1")
        }
        legacy.registerMigration("v2", foreignKeyChecks: .immediate) { db in
            try TaisaSchema.createVersion2(in: db)
            try db.execute(sql: "INSERT INTO migration_state (version, applied_at_ms) VALUES (2, 2)")
            try db.execute(sql: "PRAGMA user_version = 2")
        }
        try legacy.migrate(queue)
        try queue.close()

        let store = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let state = try await store.read { db in
            (
                try Int.fetchOne(db, sql: "PRAGMA user_version"),
                try Int.fetchOne(db, sql: "SELECT count(*) FROM conversation_drafts"),
                try Int.fetchOne(db, sql: "SELECT count(*) FROM message_revisions"),
                try String.fetchOne(db, sql: "SELECT lifecycle FROM conversations LIMIT 1")
            )
        }
        #expect(state.0 == 3)
        #expect(state.1 == 0)
        #expect(state.2 == 0)
        #expect(state.3 == nil)
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

    @Test func existingOrphanRowIsRejectedWithoutRepair() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let raw = try fixture.makeKeyedQueue(foreignKeysEnabled: false)
        try await raw.write { db in
            try db.execute(
                sql: "INSERT INTO messages (id, conversation_id, role, body, created_at_ms) VALUES (?, ?, 'user', 'orphan', 1)",
                arguments: [UUID().uuidString, UUID().uuidString]
            )
        }
        let before = try fixture.fileSnapshot()
        await #expect(throws: StorageError.integrityFailed) {
            try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        }
        #expect(try fixture.fileSnapshot() == before)
        #expect(try await fixture.keys.loadKey() == fixture.key)
        let violations = try await raw.read { db in try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").count }
        #expect(violations == 1)
    }

    @Test func existingCheckConstraintViolationIsRejected() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let raw = try fixture.makeKeyedQueue()
        try await raw.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA ignore_check_constraints = ON")
            try db.execute(
                sql: "INSERT INTO goals (id, title, status, created_at_ms, updated_at_ms) VALUES (?, 'bad', 'invalid', 1, 1)",
                arguments: [UUID().uuidString]
            )
            try db.execute(sql: "PRAGMA ignore_check_constraints = OFF")
        }
        let invalidStatus = try await raw.read { db in
            try String.fetchOne(db, sql: "SELECT status FROM goals LIMIT 1")
        }
        #expect(invalidStatus == "invalid")
        let before = try fixture.fileSnapshot()
        await #expect(throws: StorageError.integrityFailed) {
            try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        }
        #expect(try fixture.fileSnapshot() == before)
    }

    @Test func missingRequiredTableIsRejectedWithoutRepair() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let raw = try fixture.makeKeyedQueue()
        try await raw.write { db in try db.execute(sql: "DROP TABLE messages") }
        let before = try fixture.fileSnapshot()
        await #expect(throws: StorageError.schemaMismatch) {
            try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        }
        #expect(try fixture.fileSnapshot() == before)
        #expect(try await fixture.keys.loadKey() == fixture.key)
        #expect(try await raw.read { db in try !db.tableExists("messages") })
    }

    @Test func missingEssentialColumnIsRejected() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let raw = try fixture.makeKeyedQueue()
        try await raw.write { db in
            try db.execute(sql: "ALTER TABLE profile RENAME COLUMN headline TO obsolete_headline")
        }
        await #expect(throws: StorageError.schemaMismatch) {
            try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        }
    }

    @Test func mismatchedVersionMarkersAreRejected() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let raw = try fixture.makeKeyedQueue()
        try await raw.write { db in try db.execute(sql: "PRAGMA user_version = 0") }
        let before = try fixture.fileSnapshot()
        await #expect(throws: StorageError.schemaMismatch) {
            try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        }
        #expect(try fixture.fileSnapshot() == before)
    }

    @Test func missingMigrationStateIsRejected() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let raw = try fixture.makeKeyedQueue()
        try await raw.write { db in try db.execute(sql: "DELETE FROM migration_state") }
        await #expect(throws: StorageError.schemaMismatch) {
            try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        }
    }

    @Test func unknownMigrationIdentifierIsRejectedWithoutRepair() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let raw = try fixture.makeKeyedQueue()
        try await raw.write { db in try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v99')") }
        let before = try fixture.fileSnapshot()
        await #expect(throws: StorageError.unsupportedMigration) {
            try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        }
        #expect(try fixture.fileSnapshot() == before)
    }

    @Test func missingRequiredForeignKeyIsRejected() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let raw = try fixture.makeKeyedQueue(foreignKeysEnabled: false)
        try await raw.write { db in
            try db.execute(sql: "DROP TABLE messages")
            try db.execute(sql: """
                CREATE TABLE messages (
                    id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
                    conversation_id TEXT NOT NULL,
                    role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
                    body TEXT NOT NULL,
                    created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0)
                )
                """)
            try db.execute(sql: "CREATE INDEX messages_by_conversation ON messages(conversation_id, created_at_ms)")
        }
        await #expect(throws: StorageError.schemaMismatch) {
            try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        }
    }

    @Test func missingPrimaryKeyIsRejected() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let raw = try fixture.makeKeyedQueue()
        try await raw.write { db in
            try db.execute(sql: "DROP TABLE profile")
            try db.execute(sql: """
                CREATE TABLE profile (
                    id TEXT NOT NULL CHECK (length(id) = 36),
                    display_name TEXT NOT NULL DEFAULT '',
                    headline TEXT NOT NULL DEFAULT '',
                    biography TEXT NOT NULL DEFAULT '',
                    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= 0)
                )
                """)
        }
        await #expect(throws: StorageError.schemaMismatch) {
            try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        }
    }

    @Test func missingIdempotencyUniquenessIsRejected() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let raw = try fixture.makeKeyedQueue()
        try await raw.write { db in
            try db.execute(sql: "DROP TABLE outbox")
            try db.execute(sql: """
                CREATE TABLE outbox (
                    id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
                    mutation_id TEXT NOT NULL CHECK (length(mutation_id) = 36),
                    entity_type TEXT NOT NULL,
                    entity_id TEXT NOT NULL CHECK (length(entity_id) = 36),
                    payload BLOB NOT NULL,
                    status TEXT NOT NULL CHECK (status IN ('pending', 'retrying', 'acknowledged')),
                    retry_category TEXT,
                    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
                    created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0),
                    acknowledged_at_ms INTEGER CHECK (acknowledged_at_ms >= created_at_ms)
                )
                """)
            try db.execute(sql: "CREATE INDEX outbox_pending ON outbox(status, created_at_ms)")
        }
        await #expect(throws: StorageError.schemaMismatch) {
            try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        }
    }

    @Test func unknownVersionZeroSchemaIsRejectedBeforeMetadataCreation() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let raw = try fixture.makeKeyedQueue()
        try await raw.write { db in
            try db.execute(sql: "CREATE TABLE unrelated_data (id TEXT PRIMARY KEY)")
            try db.execute(sql: "INSERT INTO unrelated_data (id) VALUES ('private')")
        }
        let restarted = try fixture.restartCopy()
        let before = try fixture.fileSnapshot(at: restarted)
        await #expect(throws: StorageError.schemaMismatch) {
            try await TaisaStore.open(at: restarted, keyStore: fixture.keys)
        }
        #expect(try fixture.fileSnapshot(at: restarted) == before)
        #expect(try await fixture.keys.loadKey() == fixture.key)
        let check = try fixture.makeKeyedQueue(at: restarted, readonly: true)
        #expect(try await check.read { db in try !db.tableExists("grdb_migrations") })
        #expect(try await check.read { db in try !db.tableExists("profile") })
    }

    @Test func sqliteXdataVersionZeroSchemaIsRejectedBeforeMetadataCreation() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let raw = try fixture.makeKeyedQueue()
        try await raw.write { db in
            try db.execute(sql: "CREATE TABLE sqliteXdata (id TEXT PRIMARY KEY)")
            try db.execute(sql: "INSERT INTO sqliteXdata (id) VALUES ('private')")
        }
        let restarted = try fixture.restartCopy()
        let before = try fixture.fileSnapshot(at: restarted)
        await #expect(throws: StorageError.schemaMismatch) {
            try await TaisaStore.open(at: restarted, keyStore: fixture.keys)
        }
        #expect(try fixture.fileSnapshot(at: restarted) == before)
        #expect(try await fixture.keys.loadKey() == fixture.key)
        let check = try fixture.makeKeyedQueue(at: restarted, readonly: true)
        #expect(try await check.read { db in try !db.tableExists("grdb_migrations") })
        #expect(try await check.read { db in try !db.tableExists("profile") })
    }

    @Test func emptyExistingVersionZeroSchemaInitializes() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try fixture.makeKeyedQueue()
        let restarted = try fixture.restartCopy()
        let store = try await TaisaStore.open(at: restarted, keyStore: fixture.keys)
        #expect(try await store.read { db in try db.tableExists("profile") })
        #expect(try await store.read { db in try Int.fetchOne(db, sql: "PRAGMA user_version") } == 3)
        #expect(try await fixture.keys.loadKey() == fixture.key)
    }

    @Test func schemaChangeAfterSnapshotIsRejectedWithoutTouchingOriginal() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let restarted = try fixture.restartCopy()
        let otherWriter = try fixture.makeKeyedQueue(at: restarted)
        let mutation = MigrationSnapshotRecorder()
        await #expect(throws: StorageError.integrityFailed) {
            try await TaisaStore.open(
                at: restarted,
                keyStore: fixture.keys,
                afterValidation: {
                    try await otherWriter.write { db in try db.execute(sql: "DROP TABLE messages") }
                    try await mutation.record(fixture.fileSnapshot(at: restarted))
                }
            )
        }
        let afterMutation = await mutation.snapshot
        #expect(afterMutation != nil)
        #expect(try fixture.fileSnapshot(at: restarted) == afterMutation)
        #expect(try await fixture.keys.loadKey() == fixture.key)
        #expect(try await otherWriter.read { db in try !db.tableExists("messages") })
    }

    @Test func schemaChangeAfterGenerationCheckCannotBePublished() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let restarted = try fixture.restartCopy()
        let otherWriter = try fixture.makeKeyedQueue(at: restarted)
        let mutation = MigrationSnapshotRecorder()
        await #expect(throws: StorageError.integrityFailed) {
            try await TaisaStore.open(
                at: restarted,
                keyStore: fixture.keys,
                afterValidation: {},
                afterGeneration: {
                    try await otherWriter.write { db in try db.execute(sql: "DROP TABLE messages") }
                    try otherWriter.close()
                    try await mutation.record(fixture.fileSnapshot(at: restarted))
                }
            )
        }
        let afterMutation = await mutation.snapshot
        #expect(afterMutation?.durableBytes["-wal"]?.isEmpty == false)
        #expect(try fixture.fileSnapshot(at: restarted) == afterMutation)
        #expect(try await fixture.keys.loadKey() == fixture.key)
        let check = try fixture.makeKeyedQueue(at: restarted, readonly: true)
        #expect(try await check.read { db in try !db.tableExists("messages") })
    }

    @Test func soleConnectionOrphanWalIsRejectedWithoutCheckpoint() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let raw = try fixture.makeKeyedQueue(foreignKeysEnabled: false)
        try await raw.write { db in
            try db.execute(
                sql: "INSERT INTO messages (id, conversation_id, role, body, created_at_ms) VALUES (?, ?, 'user', 'orphan', 1)",
                arguments: [UUID().uuidString, UUID().uuidString]
            )
        }
        let restarted = try fixture.restartCopy()
        let before = try fixture.fileSnapshot(at: restarted)
        #expect(before.durableBytes["-wal"]?.isEmpty == false)
        await #expect(throws: StorageError.integrityFailed) {
            try await TaisaStore.open(at: restarted, keyStore: fixture.keys)
        }
        #expect(try fixture.fileSnapshot(at: restarted) == before)
        #expect(try await fixture.keys.loadKey() == fixture.key)
    }

    @Test func soleConnectionDamagedSchemaWalIsRejectedWithoutCheckpoint() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let raw = try fixture.makeKeyedQueue()
        try await raw.write { db in try db.execute(sql: "DROP TABLE messages") }
        let restarted = try fixture.restartCopy()
        let before = try fixture.fileSnapshot(at: restarted)
        #expect(before.durableBytes["-wal"]?.isEmpty == false)
        await #expect(throws: StorageError.schemaMismatch) {
            try await TaisaStore.open(at: restarted, keyStore: fixture.keys)
        }
        #expect(try fixture.fileSnapshot(at: restarted) == before)
        #expect(try await fixture.keys.loadKey() == fixture.key)
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

    func makeKeyedQueue(
        at target: URL? = nil,
        foreignKeysEnabled: Bool = true,
        readonly: Bool = false
    ) throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = foreignKeysEnabled
        configuration.readonly = readonly
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA key = \"x'000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f'\"")
        }
        return try DatabaseQueue(path: (target ?? url).path, configuration: configuration)
    }

    func restartCopy() throws -> URL {
        let restarted = directory.appendingPathComponent(UUID().uuidString + ".sqlite")
        // Source writers are idle while these files are copied; the copied
        // target has no open connection and retains its pending WAL.
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.copyItem(
                    at: source,
                    to: URL(fileURLWithPath: restarted.path + suffix)
                )
            }
        }
        return restarted
    }

    func fileSnapshot(at target: URL? = nil) throws -> MigrationFileSnapshot {
        var durableBytes: [String: Data] = [:]
        var fileNumbers: [String: UInt64] = [:]
        for suffix in ["", "-wal", "-shm"] {
            let path = URL(fileURLWithPath: (target ?? url).path + suffix)
            if FileManager.default.fileExists(atPath: path.path) {
                let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
                guard let number = attributes[.systemFileNumber] as? NSNumber else {
                    throw CocoaError(.fileReadUnknown)
                }
                fileNumbers[suffix] = number.uint64Value
                // SQLite changes -shm reader slots even for a rejected open.
                if suffix != "-shm" { durableBytes[suffix] = try Data(contentsOf: path) }
            }
        }
        return MigrationFileSnapshot(durableBytes: durableBytes, fileNumbers: fileNumbers)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private struct MigrationFileSnapshot: Equatable, Sendable {
    let durableBytes: [String: Data]
    let fileNumbers: [String: UInt64]
}

private actor MigrationSnapshotRecorder {
    private(set) var snapshot: MigrationFileSnapshot?
    func record(_ value: MigrationFileSnapshot) { snapshot = value }
}

private enum MigrationInterruption: Error { case injected }

private actor FixedDatabaseKeyStore: DatabaseKeyStore {
    let key: Data
    init(key: Data) { self.key = key }
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { Issue.record("Existing fixture key must not be replaced") }
}
