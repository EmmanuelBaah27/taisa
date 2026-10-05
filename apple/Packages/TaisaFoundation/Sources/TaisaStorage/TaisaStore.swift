import Foundation
import GRDB

/// Serialized SQLCipher access for local repositories. Returned values cross a
/// concurrency boundary, so callers must return Sendable data, never a GRDB row.
public final class TaisaStore: Sendable {
    private let queue: DatabaseQueue

    private struct SourceGeneration: Equatable {
        let dataVersion: Int
        let fileIDs: [String: UInt64]
    }

    private init(queue: DatabaseQueue) { self.queue = queue }

    public static func open(
        at url: URL,
        keyStore: any DatabaseKeyStore = KeychainStore()
    ) async throws -> TaisaStore {
        try await open(at: url, keyStore: keyStore, afterValidation: {})
    }

    // Deterministic test boundary: runs after the disposable snapshot has
    // passed inspection, before the source is opened for normal use.
    static func open(
        at url: URL,
        keyStore: any DatabaseKeyStore,
        afterValidation: @Sendable () async throws -> Void
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
        configuration.readonly = existed
        configuration.prepareDatabase { db in
            try db.usePassphrase(rawKey)
        }

        // An existing source is opened read-only so rejection cannot checkpoint
        // its pending WAL. SQLite's online backup yields a consistent view of
        // main + WAL in a disposable encrypted file for full integrity checks.
        let validationQueue: DatabaseQueue
        do {
            validationQueue = try DatabaseQueue(path: url.path, configuration: configuration)
        } catch let error as DatabaseError where error.resultCode == .SQLITE_NOTADB {
            throw StorageError.authenticationFailed
        } catch {
            throw StorageError.openFailed
        }

        // A read-only connection's data_version changes on commits from any
        // other SQLite connection. Together with file identities, this binds
        // the inspected backup to the same source generation at handoff.
        let sourceGeneration = existed ? try generation(of: validationQueue, at: url) : nil

        let inspectionQueue: DatabaseQueue
        var validationDirectory: URL?
        defer {
            if let validationDirectory {
                try? FileManager.default.removeItem(at: validationDirectory)
            }
        }
        if existed {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("taisa-validation-\(UUID().uuidString)")
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700]
                )
                validationDirectory = directory
                let copyURL = directory.appendingPathComponent("inspection.sqlite")
                guard FileManager.default.createFile(
                    atPath: copyURL.path,
                    contents: nil,
                    attributes: [.posixPermissions: 0o600]
                ) else { throw StorageError.integrityFailed }
                var copyConfiguration = configuration
                copyConfiguration.readonly = false
                let copy = try DatabaseQueue(
                    path: copyURL.path,
                    configuration: copyConfiguration
                )
                try validationQueue.backup(to: copy)
                inspectionQueue = copy
            } catch {
                throw StorageError.integrityFailed
            }
        } else {
            inspectionQueue = validationQueue
        }

        do {
            try await inspectionQueue.read { db in
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
                guard try String.fetchAll(db, sql: "PRAGMA integrity_check") == ["ok"] else {
                    throw StorageError.integrityFailed
                }
                guard try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty else {
                    throw StorageError.integrityFailed
                }
            }
        } catch let error as StorageError {
            throw error
        } catch let error as DatabaseError where error.resultCode == .SQLITE_NOTADB {
            throw StorageError.authenticationFailed
        } catch {
            throw StorageError.integrityFailed
        }

        let version = try TaisaMigrator.preflight(inspectionQueue)
        try await afterValidation()
        if let sourceGeneration {
            guard try generation(of: validationQueue, at: url) == sourceGeneration else {
                throw StorageError.integrityFailed
            }
        }
        let queue: DatabaseQueue
        if existed {
            configuration.readonly = false
            do {
                queue = try DatabaseQueue(path: url.path, configuration: configuration)
            } catch let error as DatabaseError where error.resultCode == .SQLITE_NOTADB {
                throw StorageError.authenticationFailed
            } catch {
                throw StorageError.openFailed
            }
        } else {
            queue = validationQueue
        }
        try TaisaMigrator.migrate(queue, from: version)
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

    private static func generation(of queue: DatabaseQueue, at url: URL) throws -> SourceGeneration {
        do {
            let before = try queue.read { db in
                try Int.fetchOne(db, sql: "PRAGMA data_version")
            }
            var fileIDs: [String: UInt64] = [:]
            for suffix in ["", "-wal"] {
                let path = url.path + suffix
                if FileManager.default.fileExists(atPath: path) {
                    let attributes = try FileManager.default.attributesOfItem(atPath: path)
                    guard let number = attributes[.systemFileNumber] as? NSNumber else {
                        throw StorageError.integrityFailed
                    }
                    fileIDs[suffix] = number.uint64Value
                }
            }
            let after = try queue.read { db in
                try Int.fetchOne(db, sql: "PRAGMA data_version")
            }
            guard let before, before == after, fileIDs[""] != nil else {
                throw StorageError.integrityFailed
            }
            return SourceGeneration(dataVersion: before, fileIDs: fileIDs)
        } catch {
            throw StorageError.integrityFailed
        }
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
