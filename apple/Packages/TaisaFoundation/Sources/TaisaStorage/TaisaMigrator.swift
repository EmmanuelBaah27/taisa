import Foundation
import GRDB

enum TaisaMigrator {
    static func preflight(_ queue: DatabaseQueue) throws -> Int {
        try TaisaSchema.validateMigrationLedger(TaisaSchema.migrationLedger)
        let version: Int
        do {
            version = try queue.read { db in
                try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
            }
        } catch {
            throw StorageError.migrationFailed
        }
        guard version >= 0, version <= TaisaSchema.currentVersion else {
            throw StorageError.unsupportedSchemaVersion(version)
        }
        do {
            try queue.read { db in
                let hasGRDBMarkers = try db.tableExists("grdb_migrations")
                let applied = hasGRDBMarkers
                    ? try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
                    : []
                let supportedIdentifiers = Set(TaisaSchema.migrationLedger.map(\.identifier))
                guard applied.allSatisfy(supportedIdentifiers.contains) else {
                    throw StorageError.unsupportedMigration
                }
                if version == 1 {
                    guard applied == ["v1"] else { throw StorageError.schemaMismatch }
                    try TaisaSchema.validateVersion1(in: db)
                    let states = try Int.fetchAll(db, sql: "SELECT version FROM migration_state ORDER BY version")
                    guard states == [1] else { throw StorageError.schemaMismatch }
                } else if version == 2 {
                    guard applied == ["v1", "v2"] else { throw StorageError.schemaMismatch }
                    try TaisaSchema.validateVersion2(in: db)
                    let states = try Int.fetchAll(db, sql: "SELECT version FROM migration_state ORDER BY version")
                    guard states == [1, 2] else { throw StorageError.schemaMismatch }
                } else if version == 3 {
                    guard applied == ["v1", "v2", "v3"] else { throw StorageError.schemaMismatch }
                    try TaisaSchema.validateVersion3(in: db)
                    let states = try Int.fetchAll(db, sql: "SELECT version FROM migration_state ORDER BY version")
                    guard states == [1, 2, 3] else { throw StorageError.schemaMismatch }
                } else if version == 4 {
                    guard applied == ["v1", "v2", "v3", "v4"] else { throw StorageError.schemaMismatch }
                    try TaisaSchema.validateVersion4(in: db)
                    let states = try Int.fetchAll(db, sql: "SELECT version FROM migration_state ORDER BY version")
                    guard states == [1, 2, 3, 4] else { throw StorageError.schemaMismatch }
                } else if version == 5 {
                    guard applied == ["v1", "v2", "v3", "v4", "v5"] else { throw StorageError.schemaMismatch }
                    try TaisaSchema.validateVersion5(in: db)
                    let states = try Int.fetchAll(db, sql: "SELECT version FROM migration_state ORDER BY version")
                    guard states == [1, 2, 3, 4, 5] else { throw StorageError.schemaMismatch }
                } else {
                    let objects = try String.fetchAll(
                        db,
                        sql: "SELECT name FROM sqlite_master WHERE substr(name, 1, 7) != 'sqlite_' AND type IN ('table', 'view', 'trigger', 'index') LIMIT 1"
                    )
                    guard applied.isEmpty, objects.isEmpty else {
                        throw StorageError.schemaMismatch
                    }
                }
            }
        } catch let error as StorageError {
            throw error
        } catch {
            throw StorageError.schemaMismatch
        }
        return version
    }

    static func migrate(
        _ queue: DatabaseQueue,
        from version: Int,
        createSchema: @escaping @Sendable (Database) throws -> Void = TaisaSchema.createVersion1,
        createVersion3: @escaping @Sendable (Database) throws -> Void = TaisaSchema.createVersion3,
        createVersion5: @escaping @Sendable (Database) throws -> Void = TaisaSchema.createVersion5
    ) throws {
        // The caller completes a read-only preflight on any existing file.
        if version == TaisaSchema.currentVersion { return }

        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1", foreignKeyChecks: .immediate) { db in
            try createSchema(db)
            try db.execute(
                sql: "INSERT INTO migration_state (version, applied_at_ms) VALUES (?, ?)",
                arguments: [1, Int64(Date().timeIntervalSince1970 * 1_000)]
            )
            try db.execute(sql: "PRAGMA user_version = 1")
        }
        migrator.registerMigration("v2", foreignKeyChecks: .immediate) { db in
            try TaisaSchema.createVersion2(in: db)
            try db.execute(
                sql: "INSERT INTO migration_state (version, applied_at_ms) VALUES (?, ?)",
                arguments: [2, Int64(Date().timeIntervalSince1970 * 1_000)]
            )
            try db.execute(sql: "PRAGMA user_version = 2")
        }
        migrator.registerMigration("v3", foreignKeyChecks: .immediate) { db in
            try createVersion3(db)
            try db.execute(
                sql: "INSERT INTO migration_state (version, applied_at_ms) VALUES (?, ?)",
                arguments: [3, Int64(Date().timeIntervalSince1970 * 1_000)]
            )
            try db.execute(sql: "PRAGMA user_version = 3")
        }
        migrator.registerMigration("v4", foreignKeyChecks: .immediate) { db in
            try TaisaSchema.createVersion4(in: db)
            try db.execute(
                sql: "INSERT INTO migration_state (version, applied_at_ms) VALUES (?, ?)",
                arguments: [4, Int64(Date().timeIntervalSince1970 * 1_000)]
            )
            try db.execute(sql: "PRAGMA user_version = 4")
        }
        migrator.registerMigration("v5", foreignKeyChecks: .immediate) { db in
            try createVersion5(db)
            try db.execute(
                sql: "INSERT INTO migration_state (version, applied_at_ms) VALUES (?, ?)",
                arguments: [5, Int64(Date().timeIntervalSince1970 * 1_000)]
            )
            try db.execute(sql: "PRAGMA user_version = 5")
        }
        do {
            try migrator.migrate(queue)
            guard try preflight(queue) == TaisaSchema.currentVersion else {
                throw StorageError.migrationFailed
            }
        } catch {
            throw StorageError.migrationFailed
        }
    }
}
