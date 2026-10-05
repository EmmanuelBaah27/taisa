import Foundation
import GRDB

/// Serialized SQLCipher access for local repositories. Returned values cross a
/// concurrency boundary, so callers must return Sendable data, never a GRDB row.
public final class TaisaStore: Sendable {
    private let queue: DatabaseQueue
    private let lifecycle: StoreLifecycle

    private struct SourceGeneration: Equatable {
        let dataVersion: Int
        let fileIDs: [String: UInt64]
    }

    private init(queue: DatabaseQueue, lifecycle: StoreLifecycle) {
        self.queue = queue
        self.lifecycle = lifecycle
    }

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
        afterValidation: @Sendable () async throws -> Void,
        afterGeneration: @Sendable () async throws -> Void = {}
    ) async throws -> TaisaStore {
        let lifecycle = await StoreLifecycleRegistry.shared.lifecycle(for: url)
        return try await lifecycle.exclusive {
            try await openUnderLifecycle(
                at: url,
                keyStore: keyStore,
                lifecycle: lifecycle,
                afterValidation: afterValidation,
                afterGeneration: afterGeneration
            )
        }
    }

    private static func openUnderLifecycle(
        at url: URL,
        keyStore: any DatabaseKeyStore,
        lifecycle: StoreLifecycle,
        afterValidation: @Sendable () async throws -> Void,
        afterGeneration: @Sendable () async throws -> Void
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
        try await afterGeneration()
        // This is the validation publication point for TaisaStore writers:
        // every supported open/write for this canonical path holds the same
        // lifecycle ownership, so none can change the source before return.
        // Independently keyed SQLite writers are outside that contract; a
        // commit already completed here is detected without opening the
        // original writable, but later arbitrary commits cannot be excluded.
        if let sourceGeneration {
            guard try generation(of: validationQueue, at: url) == sourceGeneration else {
                throw StorageError.integrityFailed
            }
            guard try TaisaMigrator.preflight(validationQueue) == version,
                  try generation(of: validationQueue, at: url) == sourceGeneration else {
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
        return TaisaStore(queue: queue, lifecycle: lifecycle)
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
        try await lifecycle.exclusive {
            try await queue.write(body)
        }
    }
}

/// Process-local ownership for the supported TaisaStore open/write lifecycle.
/// Callers must use one canonical URL for a store; independent SQLite handles
/// and external filesystem replacement are not participants in this gate.
private actor StoreLifecycleRegistry {
    static let shared = StoreLifecycleRegistry()
    private var lifecycles: [String: StoreLifecycle] = [:]

    func lifecycle(for url: URL) -> StoreLifecycle {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        if let lifecycle = lifecycles[path] { return lifecycle }
        let lifecycle = StoreLifecycle()
        lifecycles[path] = lifecycle
        return lifecycle
    }
}

private actor StoreLifecycle {
    private var occupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func exclusive<Value: Sendable>(
        _ body: @Sendable () async throws -> Value
    ) async throws -> Value {
        await acquire()
        defer { release() }
        return try await body()
    }

    private func acquire() async {
        if !occupied {
            occupied = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            occupied = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
