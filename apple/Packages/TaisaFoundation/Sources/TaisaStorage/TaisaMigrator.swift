import Foundation
import GRDB

enum TaisaMigrator {
    static func migrate(_ queue: DatabaseQueue) throws {
        let version: Int
        do {
            version = try queue.read { db in
                try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
            }
        } catch {
            throw StorageError.migrationFailed
        }
        guard version <= TaisaSchema.currentVersion else {
            throw StorageError.unsupportedSchemaVersion(version)
        }

        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1", foreignKeyChecks: .immediate) { db in
            try TaisaSchema.createVersion1(in: db)
            try db.execute(
                sql: "INSERT INTO migration_state (version, applied_at_ms) VALUES (?, ?)",
                arguments: [1, Int64(Date().timeIntervalSince1970 * 1_000)]
            )
            try db.execute(sql: "PRAGMA user_version = 1")
        }
        do {
            try migrator.migrate(queue)
            let finalVersion = try queue.read { db in
                try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
            }
            guard finalVersion == TaisaSchema.currentVersion else {
                throw StorageError.migrationFailed
            }
        } catch {
            throw StorageError.migrationFailed
        }
    }
}
