import Foundation
import GRDB

enum TaisaMigrator {
    static func preflight(_ queue: DatabaseQueue) throws -> Int {
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
                guard applied.allSatisfy({ $0 == "v1" }) else {
                    throw StorageError.unsupportedMigration
                }
                if version == 1 {
                    guard applied == ["v1"] else { throw StorageError.schemaMismatch }
                    try TaisaSchema.validateVersion1(in: db)
                    let states = try Int.fetchAll(db, sql: "SELECT version FROM migration_state ORDER BY version")
                    guard states == [1] else { throw StorageError.schemaMismatch }
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
        createSchema: @escaping @Sendable (Database) throws -> Void = TaisaSchema.createVersion1
    ) throws {
        // The caller completes a read-only preflight on any existing file.
        if version == 1 { return }

        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1", foreignKeyChecks: .immediate) { db in
            try createSchema(db)
            try db.execute(
                sql: "INSERT INTO migration_state (version, applied_at_ms) VALUES (?, ?)",
                arguments: [1, Int64(Date().timeIntervalSince1970 * 1_000)]
            )
            try db.execute(sql: "PRAGMA user_version = 1")
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
