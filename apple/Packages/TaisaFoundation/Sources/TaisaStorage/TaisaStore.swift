import Foundation
import GRDB

/// Serialized SQLCipher access for local repositories. Returned values cross a
/// concurrency boundary, so callers must return Sendable data, never a GRDB row.
public final class TaisaStore: Sendable {
    private let queue: DatabaseQueue

    private init(queue: DatabaseQueue) { self.queue = queue }

    public static func open(
        at url: URL,
        keyStore: any DatabaseKeyStore = KeychainStore()
    ) async throws -> TaisaStore {
        // This decision precedes any key creation. Missing Keychain material for
        // an existing file is a recovery state, never permission to replace it.
        let existed = FileManager.default.fileExists(atPath: url.path)
        let storedKey = try await keyStore.loadKey()
        guard !existed || storedKey != nil else {
            throw StorageError.missingKeyForExistingStore
        }

        let key: Data
        if let storedKey {
            key = storedKey
        } else {
            key = try DatabaseKeyGenerator.generate()
            // Refuse a concurrent file appearance before persisting a new key.
            guard !FileManager.default.fileExists(atPath: url.path) else {
                throw StorageError.missingKeyForExistingStore
            }
            try await keyStore.saveKey(key)
        }
        guard key.count == 32 else { throw StorageError.invalidKeyLength }

        // SQLCipher's x'<64 hex>' form uses the 32 bytes directly. A bare Data
        // passphrase would instead run PBKDF2 and break the Task 1 raw-key contract.
        let rawKey = Data(("x'" + key.map { String(format: "%02x", $0) }.joined() + "'").utf8)
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.prepareDatabase { db in
            try db.usePassphrase(rawKey)
        }

        let queue: DatabaseQueue
        do {
            queue = try DatabaseQueue(path: url.path, configuration: configuration)
        } catch let error as DatabaseError where error.resultCode == .SQLITE_NOTADB {
            throw StorageError.authenticationFailed
        } catch {
            throw StorageError.openFailed
        }

        do {
            try await queue.read { db in
                guard let cipherVersion = try String.fetchOne(db, sql: "PRAGMA cipher_version"),
                      !cipherVersion.isEmpty else {
                    throw StorageError.cipherUnavailable
                }
                _ = try Int.fetchOne(db, sql: "PRAGMA user_version")
                guard try Int.fetchOne(db, sql: "PRAGMA foreign_keys") == 1 else {
                    throw StorageError.configurationFailed
                }
                guard try String.fetchAll(db, sql: "PRAGMA cipher_integrity_check").isEmpty else {
                    throw StorageError.integrityFailed
                }
            }
        } catch let error as StorageError {
            throw error
        } catch let error as DatabaseError where error.resultCode == .SQLITE_NOTADB {
            throw StorageError.authenticationFailed
        } catch {
            throw StorageError.openFailed
        }

        try TaisaMigrator.migrate(queue)
        do {
            try await queue.writeWithoutTransaction { db in
                let journalMode = try String.fetchOne(db, sql: "PRAGMA journal_mode = WAL")
                guard journalMode?.lowercased() == "wal" else {
                    throw StorageError.configurationFailed
                }
            }
        } catch let error as StorageError {
            throw error
        } catch {
            throw StorageError.configurationFailed
        }
        return TaisaStore(queue: queue)
    }

    public func read<Value: Sendable>(
        _ body: @Sendable (Database) throws -> Value
    ) async throws -> Value {
        try await queue.read(body)
    }

    public func write<Value: Sendable>(
        _ body: @Sendable (Database) throws -> Value
    ) async throws -> Value {
        try await queue.write(body)
    }
}
