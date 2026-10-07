import Foundation
import GRDB
import CryptoKit
import Darwin

/// Digest and size describe the encrypted SQLCipher file before outer framing.
public struct CheckpointMetadata: Equatable, Sendable {
    public let schemaVersion: Int
    public let entityCounts: [String: Int]
    public let plaintextByteCount: Int64
    public let plaintextSHA256: Data
}

/// Serialized SQLCipher access for local repositories. Returned values cross a
/// concurrency boundary, so callers must return Sendable data, never a GRDB row.
public final class TaisaStore: Sendable {
    public static var currentSchemaVersion: Int { TaisaSchema.currentVersion }
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
        let canonicalURL = StoreDatabaseIdentity.canonicalURL(for: url)
        let lifecycle = await StoreLifecycleRegistry.shared.lifecycle(for: canonicalURL)
        return try await lifecycle.exclusive {
            try await openUnderLifecycle(
                at: canonicalURL,
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
        // Recovery must settle the database/key exchange before a normal open
        // can create, migrate, or checkpoint any file at this path.
        try StoreDatabaseIdentity.assertNoPendingRestore(at: url)
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
        await lifecycle.register(queue)
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
        try await lifecycle.read(queue: queue) { try await queue.read(body) }
    }

    /// Holds the canonical store gate across backup, closing every supported
    /// handle, exchange, Keychain update and rollback. `prepare` runs while all
    /// handles are quiescent, before close can checkpoint the original WAL.
    /// The caller must recover an outstanding restore journal before normal open.
    public static func withExclusiveReplacement<Value: Sendable>(
        at url: URL,
        prepare: @escaping @Sendable () async throws -> Void = {},
        body: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let lifecycle = await StoreLifecycleRegistry.shared.lifecycle(for: StoreDatabaseIdentity.canonicalURL(for: url))
        return try await lifecycle.exclusive {
            await lifecycle.beginReplacement()
            do {
                try await prepare()
                try await lifecycle.closeHandles()
                let result = try await body()
                await lifecycle.endReplacement()
                return result
            } catch {
                await lifecycle.endReplacement()
                throw error
            }
        }
    }

    /// Private candidate only: verify current schema and integrity, then change
    /// its SQLCipher key and leave a closed, single-file database for promotion.
    public func rekeyRestoreCandidate(to key: Data) async throws -> [String: Int] {
        guard key.count == 32 else { throw StorageError.invalidKeyLength }
        return try await lifecycle.exclusive {
            try await self.lifecycle.assertOpen(self.queue)
            guard try TaisaMigrator.preflight(self.queue) == TaisaSchema.currentVersion else { throw StorageError.schemaMismatch }
            let counts = try await self.queue.read { db in
                guard try String.fetchAll(db, sql: "PRAGMA cipher_integrity_check").isEmpty,
                      try String.fetchAll(db, sql: "PRAGMA integrity_check") == ["ok"],
                      try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty else { throw StorageError.integrityFailed }
                var counts: [String: Int] = [:]
                for table in try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND substr(name, 1, 7) != 'sqlite_' ORDER BY name") {
                    counts[table] = try Int.fetchOne(db, sql: "SELECT count(*) FROM \"\(table)\"")
                }
                return counts
            }
            try await self.queue.writeWithoutTransaction { db in
                guard let row = try Row.fetchOne(db, sql: "PRAGMA wal_checkpoint(TRUNCATE)"), (row[0] as Int) == 0,
                      try String.fetchOne(db, sql: "PRAGMA journal_mode = DELETE")?.lowercased() == "delete" else { throw StorageError.integrityFailed }
                let raw = Data(("x'" + key.map { String(format: "%02x", $0) }.joined() + "'").utf8)
                try db.changePassphrase(raw)
                guard try String.fetchAll(db, sql: "PRAGMA cipher_integrity_check").isEmpty,
                      try String.fetchAll(db, sql: "PRAGMA integrity_check") == ["ok"] else { throw StorageError.integrityFailed }
            }
            try self.queue.close()
            await self.lifecycle.markClosed(self.queue)
            return counts
        }
    }

    /// Read-only validation under an already-owned replacement gate. Does not
    /// open a normal store, migrate, create files, or register writable handles.
    public static func validateReplacement(at url: URL, key: Data, expectedSchemaVersion: Int? = nil) throws {
        guard key.count == 32 else { throw StorageError.invalidKeyLength }
        var configuration = Configuration(); configuration.readonly = true; configuration.foreignKeysEnabled = true
        let raw = Data(("x'" + key.map { String(format: "%02x", $0) }.joined() + "'").utf8)
        configuration.prepareDatabase { try $0.usePassphrase(raw) }
        let queue = try DatabaseQueue(path: url.path, configuration: configuration)
        defer { try? queue.close() }
        let version = try TaisaMigrator.preflight(queue)
        if let expectedSchemaVersion, version != expectedSchemaVersion { throw StorageError.schemaMismatch }
        try queue.read { db in
            guard try String.fetchAll(db, sql: "PRAGMA cipher_integrity_check").isEmpty,
                  try String.fetchAll(db, sql: "PRAGMA integrity_check") == ["ok"],
                  try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty else { throw StorageError.integrityFailed }
        }
    }

    /// A fresh, independently keyed SQLCipher checkpoint. Never overwrites a file.
    /// All supported source writers hold this same lifecycle gate.
    public func exportCheckpoint(to url: URL, archiveDatabaseKey: Data) async throws -> CheckpointMetadata {
        guard archiveDatabaseKey.count == 32 else { throw StorageError.invalidKeyLength }
        return try await lifecycle.exclusive {
            try await self.lifecycle.assertOpen(self.queue)
            try Task.checkCancellation()
            var created = false
            var complete = false
            defer {
                if created && !complete {
                    for suffix in ["", "-wal", "-shm", "-journal"] {
                        try? FileManager.default.removeItem(atPath: url.path + suffix)
                    }
                }
            }
            do {
                guard try TaisaMigrator.preflight(self.queue) == TaisaSchema.currentVersion else {
                    throw StorageError.schemaMismatch
                }
                try await self.queue.writeWithoutTransaction { db in
                    let result = try Row.fetchOne(db, sql: "PRAGMA wal_checkpoint(TRUNCATE)")
                    guard let result, (result[0] as Int) == 0 else { throw StorageError.integrityFailed }
                }
                let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
                guard descriptor >= 0 else { throw StorageError.openFailed }
                created = true
                Darwin.close(descriptor)
                var configuration = Configuration()
                configuration.foreignKeysEnabled = true
                let rawKey = Data(("x'" + archiveDatabaseKey.map { String(format: "%02x", $0) }.joined() + "'").utf8)
                configuration.prepareDatabase { try $0.usePassphrase(rawKey) }
                let copy = try DatabaseQueue(path: url.path, configuration: configuration)
                defer { try? copy.close() }
                try self.queue.backup(to: copy)
                let schemaVersion = try TaisaMigrator.preflight(copy)
                let counts = try await copy.read { db in
                    guard try String.fetchAll(db, sql: "PRAGMA cipher_integrity_check").isEmpty,
                          try String.fetchAll(db, sql: "PRAGMA integrity_check") == ["ok"],
                          try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty else {
                        throw StorageError.integrityFailed
                    }
                    let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND substr(name, 1, 7) != 'sqlite_' ORDER BY name")
                    var counts: [String: Int] = [:]
                    // Schema preflight above admits only the canonical table identifiers.
                    for table in tables { counts[table] = try Int.fetchOne(db, sql: "SELECT count(*) FROM \"\(table)\"") }
                    return counts
                }
                try copy.close()
                let file = try FileHandle(forReadingFrom: url)
                defer { try? file.close() }
                var hash = SHA256()
                var size: Int64 = 0
                while let data = try file.read(upToCount: 1_048_576), !data.isEmpty {
                    try Task.checkCancellation()
                    hash.update(data: data); size += Int64(data.count)
                }
                complete = true
                return CheckpointMetadata(schemaVersion: schemaVersion, entityCounts: counts,
                                          plaintextByteCount: size, plaintextSHA256: Data(hash.finalize()))
            } catch is CancellationError { throw CancellationError() }
            catch let error as StorageError { throw error }
            catch { throw StorageError.integrityFailed }
        }
    }

    public func write<Value: Sendable>(
        _ body: @Sendable (Database) throws -> Value
    ) async throws -> Value {
        try await lifecycle.exclusive {
            try await lifecycle.assertOpen(queue)
            return try await queue.write(body)
        }
    }
}

/// Process-local ownership for the supported TaisaStore open/write lifecycle.
/// Callers must use one canonical URL for a store; independent SQLite handles
/// and external filesystem replacement are not participants in this gate.
private enum StoreDatabaseIdentity {
    static func assertNoPendingRestore(at url: URL) throws {
        let journal = url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".restore-journal")
        var status = stat()
        guard lstat(journal.path, &status) != 0, errno == ENOENT else { throw StorageError.openFailed }
    }

    static func canonicalURL(for url: URL) -> URL {
        // Resolve only an existing ancestor. Foundation can resolve the same
        // /private/tmp child differently before and after SQLite creates it.
        // Re-appending normalized missing components keeps that identity
        // stable while collapsing /private/tmp, /tmp, and symlinked parents.
        var ancestor = url.standardizedFileURL
        var missingComponents: [String] = []
        while !FileManager.default.fileExists(atPath: ancestor.path) {
            let parent = ancestor.deletingLastPathComponent()
            if parent.path == ancestor.path { break }
            missingComponents.insert(ancestor.lastPathComponent, at: 0)
            ancestor = parent
        }
        var canonical = ancestor.resolvingSymlinksInPath()
        for component in missingComponents {
            canonical.appendPathComponent(component)
        }
        return canonical.standardizedFileURL
    }
}

private actor StoreLifecycleRegistry {
    static let shared = StoreLifecycleRegistry()
    private var lifecycles: [String: WeakStoreLifecycle] = [:]

    func lifecycle(for url: URL) -> StoreLifecycle {
        let path = url.path
        if let lifecycle = lifecycles[path]?.value { return lifecycle }
        lifecycles = lifecycles.filter { $0.value.value != nil }
        let lifecycle = StoreLifecycle(databaseURL: url)
        lifecycles[path] = WeakStoreLifecycle(lifecycle)
        return lifecycle
    }
}

private final class WeakStoreLifecycle {
    weak var value: StoreLifecycle?
    init(_ value: StoreLifecycle) { self.value = value }
}

private actor StoreLifecycle {
    private let databaseURL: URL
    init(databaseURL: URL) { self.databaseURL = databaseURL }
    private var occupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var handles: [WeakStoreQueue] = []
    private var closed: Set<ObjectIdentifier> = []
    private var replacing = false
    private var readers = 0
    private var readerWaiters: [CheckedContinuation<Void, Never>] = []
    private var drainWaiter: CheckedContinuation<Void, Never>?

    func read<Value: Sendable>(queue: DatabaseQueue, body: @Sendable () async throws -> Value) async throws -> Value {
        while replacing { await withCheckedContinuation { readerWaiters.append($0) } }
        try assertOpen(queue)
        readers += 1
        defer {
            readers -= 1
            if readers == 0 { drainWaiter?.resume(); drainWaiter = nil }
        }
        return try await body()
    }

    func beginReplacement() async {
        replacing = true
        if readers > 0 { await withCheckedContinuation { drainWaiter = $0 } }
    }

    func endReplacement() {
        replacing = false
        let waiters = readerWaiters; readerWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    func register(_ queue: DatabaseQueue) {
        closed.remove(ObjectIdentifier(queue))
        handles = handles.filter { $0.value != nil }
        handles.append(WeakStoreQueue(queue))
    }

    func closeHandles() throws {
        for handle in handles {
            if let queue = handle.value, !closed.contains(ObjectIdentifier(queue)) {
                try queue.close()
                closed.insert(ObjectIdentifier(queue))
            }
        }
        handles.removeAll()
    }

    func markClosed(_ queue: DatabaseQueue) { closed.insert(ObjectIdentifier(queue)) }
    func assertOpen(_ queue: DatabaseQueue) throws {
        guard !closed.contains(ObjectIdentifier(queue)) else { throw StorageError.openFailed }
        try StoreDatabaseIdentity.assertNoPendingRestore(at: databaseURL)
    }

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

private final class WeakStoreQueue {
    weak var value: DatabaseQueue?
    init(_ value: DatabaseQueue) { self.value = value }
}
