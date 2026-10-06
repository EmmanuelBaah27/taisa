import CryptoKit
import Darwin
import Foundation
import GRDB
import TaisaSecurity
import TaisaStorage

public struct RestoreCandidate: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let directory: URL
    public let databaseURL: URL
    public let databaseKey: Data
    public let manifest: SnapshotManifest
    fileprivate let directoryID: RestoreFileID
    fileprivate let databaseID: RestoreFileID
    fileprivate let digest: Data
    public var description: String { "RestoreCandidate(redacted)" }
    public var debugDescription: String { description }
}

public struct RestoreReceipt: Sendable {
    public let manifest: SnapshotManifest
}

private struct CandidateKeys: DatabaseKeyStore {
    let key: Data
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { throw RestoreError.keyFailure }
}

public struct RestoreCoordinator: Sendable {
    private let activeStoreURL: URL
    private let keyStore: any DatabaseKeyStore
    private let freeSpace: @Sendable (URL) throws -> Int64
    private let fault: @Sendable (RestoreFaultPoint) throws -> Void
    private let recoveryFault: @Sendable (RestoreRecoveryFaultPoint) throws -> Void
    public var journalURL: URL { activeStoreURL.deletingLastPathComponent().appendingPathComponent("." + activeStoreURL.lastPathComponent + ".restore-journal") }
    private static let suffixes = ["", "-wal", "-shm", "-journal"]

    public init(activeStoreURL: URL, keyStore: any DatabaseKeyStore,
                freeSpace: @escaping @Sendable (URL) throws -> Int64 = { url in
                    let attributes = try FileManager.default.attributesOfFileSystem(forPath: url.path)
                    guard let number = attributes[.systemFreeSize] as? NSNumber else { throw RestoreError.ioFailure }
                    return number.int64Value
                }) {
        self.init(activeStoreURL: activeStoreURL, keyStore: keyStore, freeSpace: freeSpace, fault: { _ in })
    }

    init(activeStoreURL: URL, keyStore: any DatabaseKeyStore,
         freeSpace: @escaping @Sendable (URL) throws -> Int64,
         fault: @escaping @Sendable (RestoreFaultPoint) throws -> Void,
         recoveryFault: @escaping @Sendable (RestoreRecoveryFaultPoint) throws -> Void = { _ in }) {
        self.activeStoreURL = activeStoreURL.standardizedFileURL
        self.keyStore = keyStore; self.freeSpace = freeSpace; self.fault = fault
        self.recoveryFault = recoveryFault
    }

    public func validate(archiveURL: URL, recoveryKey: RecoveryKey) async throws -> RestoreCandidate {
        try Task.checkCancellation()
        let root = try RestoreDirectory(activeStoreURL.deletingLastPathComponent())
        guard try root.info(journalURL.lastPathComponent) == nil else { throw RestoreError.recoveryRequired }
        guard archiveURL.isFileURL else { throw RestoreError.ioFailure }
        let descriptor = Darwin.open(archiveURL.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw RestoreError.ioFailure }
        let input = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? input.close() }
        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG, status.st_size > 0 else { throw RestoreError.ioFailure }
        let size = Int64(status.st_size)
        guard size <= (Int64.max - 100_000_000) / 2,
              try freeSpace(root.url) >= size * 2 + 100_000_000 else { throw RestoreError.insufficientCapacity }
        let name = ".taisa-restore-" + UUID().uuidString
        guard mkdirat(root.fd, name, 0o700) == 0 else { throw RestoreError.ioFailure }
        let directory = try RestoreDirectory(root.url.appendingPathComponent(name), privateOnly: true)
        let databaseURL = directory.url.appendingPathComponent("candidate.sqlite")
        var accepted = false
        let output = try directory.file("candidate.sqlite", create: true)
        guard let initialInfo = try directory.info("candidate.sqlite") else { throw RestoreError.ioFailure }
        let initialID = RestoreFileID(initialInfo)
        defer { if !accepted { try? cleanupCandidate(directory, root: root, identity: initialID) } }
        defer { try? output.close() }
        var salt = Data()
        let manifest = try PortableArchive.verify(file: input, recoveryKey: recoveryKey, maximumPayloadBytes: 1_073_741_824,
            receiveSalt: { salt = $0 }, receivePayload: { try output.write(contentsOf: $0) })
        try output.synchronize(); try output.close()
        // v1 is the only supported snapshot schema; opening may never silently
        // upgrade a manifest into something different from what was verified.
        guard manifest.schemaVersion == 1 else { throw RestoreError.incompatibleSchema }
        let archiveKey = try recoveryKey.derivePortableBackupKey(salt: salt, purpose: .database).withUnsafeBytes { Data($0) }
        try directory.require("candidate.sqlite", initialID); try directory.check(); try root.check()
        try TaisaStore.validateReplacement(at: databaseURL, key: archiveKey, expectedSchemaVersion: manifest.schemaVersion)
        let store = try await TaisaStore.open(at: databaseURL, keyStore: CandidateKeys(key: archiveKey))
        let localKey = try PortableArchive.randomSalt()
        let counts = try await store.rekeyRestoreCandidate(to: localKey)
        guard counts == manifest.entityCounts else { throw RestoreError.invalidCandidate }
        try TaisaStore.validateReplacement(at: databaseURL, key: localKey)
        try directory.check(); try root.check()
        let file = try directory.file("candidate.sqlite"); defer { try? file.close() }
        try file.synchronize(); try directory.sync()
        guard let info = try directory.info("candidate.sqlite") else { throw RestoreError.invalidCandidate }
        guard RestoreFileID(info) == initialID else { throw RestoreError.invalidCandidate }
        let candidate = RestoreCandidate(directory: directory.url, databaseURL: databaseURL, databaseKey: localKey,
            manifest: manifest, directoryID: directory.identity, databaseID: RestoreFileID(info), digest: try digest(file))
        try Task.checkCancellation()
        accepted = true
        return candidate
    }

    public func promote(_ candidate: RestoreCandidate,
                        confirmReplacement: @Sendable () async throws -> Bool) async throws -> RestoreReceipt {
        let root = try RestoreDirectory(activeStoreURL.deletingLastPathComponent())
        let directory = try checkedCandidate(candidate, root: root)
        let journal = RestoreJournal(root: root, name: journalURL.lastPathComponent)
        do {
            guard try await confirmReplacement() else { throw RestoreError.declined }
            try Task.checkCancellation()
            _ = try checkedCandidate(candidate, root: root)
        } catch {
            try? cleanupCandidate(directory, root: root, identity: candidate.databaseID)
            throw error
        }
        do {
            return try await TaisaStore.withExclusiveReplacement(at: activeStoreURL, prepare: {
                guard try root.info(journal.name) == nil else { throw RestoreError.recoveryRequired }
                guard let originalKey = try await keyStore.loadKey(), originalKey.count == 32,
                      try root.info(activeStoreURL.lastPathComponent) != nil else { throw RestoreError.keyFailure }
                _ = try checkedCandidate(candidate, root: root)
                var originals: [String: RestoreFileID] = [:]
                var backups: [String: RestoreFileID] = [:]
                var prepared = false
                defer {
                    if !prepared, (try? root.info(journal.name)) == nil {
                        for (suffix, identity) in backups { try? directory.remove("original.sqlite" + suffix, identity: identity) }
                    }
                }
                for suffix in Self.suffixes {
                    let name = activeStoreURL.lastPathComponent + suffix
                    if let info = try root.info(name) {
                        originals[suffix] = RestoreFileID(info)
                        backups[suffix] = try root.copy(name, identity: RestoreFileID(info), to: directory, as: "original.sqlite" + suffix)
                    }
                }
                let record = RestoreRecord(phase: .prepared, directoryName: directory.url.lastPathComponent,
                    directoryID: directory.identity, candidateID: candidate.databaseID, originalIDs: originals,
                    backupIDs: backups, originalKey: originalKey, candidateKey: candidate.databaseKey)
                try journal.write(record)
                prepared = true
                try fault(.prepared)
            }, body: {
                guard let currentKey = try await keyStore.loadKey(), var record = try journal.read(key: currentKey) else { throw RestoreError.recoveryRequired }
                // Handle close may checkpoint/delete WAL, so rollback uses the
                // durable pre-close copies, never these displaced working files.
                for suffix in Self.suffixes {
                    let name = activeStoreURL.lastPathComponent + suffix
                    if let value = try root.info(name) {
                        guard let identity = record.originalIDs[suffix], RestoreFileID(value) == identity else { throw RestoreError.ioFailure }
                        try root.move(name, to: directory, as: "displaced.sqlite" + suffix, identity: identity)
                    }
                }
                try fault(.originalMoveBeforeJournal)
                record.phase = .originalMoved; try journal.write(record); try fault(.originalMoved)
                try directory.move("candidate.sqlite", to: root, as: activeStoreURL.lastPathComponent, identity: record.candidateID)
                try fault(.candidateMoveBeforeJournal)
                record.phase = .candidateMoved; try journal.write(record); try fault(.candidateMoved)
                try await keyStore.replaceKey(record.candidateKey)
                try fault(.keySaveBeforeJournal)
                record.phase = .keyCommitted; try journal.write(record); try fault(.keyCommitted)
                try root.require(activeStoreURL.lastPathComponent, record.candidateID)
                try TaisaStore.validateReplacement(at: activeStoreURL, key: record.candidateKey)
                // Commit is proven only after the newly installed store opens
                // under the persisted device-local key and passes integrity.
                guard try await keyStore.loadKey() == record.candidateKey else { throw RestoreError.keyFailure }
                record.phase = .committed; try journal.write(record); try fault(.committed)
                // A cleanup error cannot turn a proven commit into a reported
                // failed replacement. The retained journal retries on launch.
                try? finish(record, directory: directory, journal: journal)
                return RestoreReceipt(manifest: candidate.manifest)
            })
        } catch is RestoreInterruption { throw RestoreInterruption.simulatedCrash }
        catch {
            if let key = try? await keyStore.loadKey(), let record = try? journal.read(key: key), record.phase == .committed {
                try? await recoverInterruptedPromotion()
                return RestoreReceipt(manifest: candidate.manifest)
            }
            // A failed rollback deliberately retains its journal and copies.
            // Relaunch must retry recovery before any normal store open.
            if try root.info(journal.name) != nil {
                do { try await recoverInterruptedPromotion() }
                catch { throw RestoreError.recoveryRequired }
            } else { try? cleanupCandidate(directory, root: root, identity: candidate.databaseID) }
            if error is CancellationError { throw CancellationError() }
            if let known = error as? RestoreError { throw known }
            throw RestoreError.ioFailure
        }
    }

    /// Call at launch before opening repositories. Repeated calls are safe;
    /// invalid/unreadable journals fail closed and retain recovery material.
    public func recoverInterruptedPromotion() async throws {
        let root = try RestoreDirectory(activeStoreURL.deletingLastPathComponent())
        let journal = RestoreJournal(root: root, name: journalURL.lastPathComponent)
        guard try root.info(journal.name) != nil else { return }
        try await TaisaStore.withExclusiveReplacement(at: activeStoreURL, prepare: {
            guard let key = try await keyStore.loadKey(), try journal.read(key: key) != nil else { throw RestoreError.recoveryRequired }
        }, body: {
            guard let key = try await keyStore.loadKey(), let record = try journal.read(key: key) else { throw RestoreError.recoveryRequired }
            if try root.info(record.directoryName) == nil {
                // Interrupted final directory/journal cleanup. Prove that the
                // completed result is still present before dropping the marker.
                if record.phase == .committed {
                    try root.require(activeStoreURL.lastPathComponent, record.candidateID)
                    guard key == record.candidateKey else { throw RestoreError.recoveryRequired }
                    try TaisaStore.validateReplacement(at: activeStoreURL, key: key)
                } else {
                    guard key == record.originalKey else { throw RestoreError.recoveryRequired }
                    for (suffix, identity) in record.backupIDs { try root.require(activeStoreURL.lastPathComponent + suffix, identity) }
                }
                try journal.remove()
                return
            }
            let directory = try RestoreDirectory(root.url.appendingPathComponent(record.directoryName), privateOnly: true)
            guard directory.identity == record.directoryID else { throw RestoreError.recoveryRequired }
            if record.phase == .committed {
                try root.require(activeStoreURL.lastPathComponent, record.candidateID)
                guard key == record.candidateKey else { throw RestoreError.recoveryRequired }
                try TaisaStore.validateReplacement(at: activeStoreURL, key: key)
            } else {
                for suffix in Self.suffixes {
                    let name = activeStoreURL.lastPathComponent + suffix
                    let backupName = "original.sqlite" + suffix
                    let activeID = try root.info(name).map(RestoreFileID.init)
                    if let backupID = record.backupIDs[suffix] {
                        if try directory.info(backupName) != nil {
                            try directory.require(backupName, backupID)
                            if let activeID {
                                guard activeID == record.originalIDs[suffix] || (suffix.isEmpty && activeID == record.candidateID) else { throw RestoreError.recoveryRequired }
                                try root.remove(name, identity: activeID)
                            }
                            try directory.move(backupName, to: root, as: name, identity: backupID)
                            switch suffix {
                            case "": try recoveryFault(.databaseRestored)
                            case "-wal": try recoveryFault(.walRestored)
                            case "-shm": try recoveryFault(.sharedMemoryRestored)
                            default: break
                            }
                        } else {
                            // Recovery itself may have crashed after this move.
                            guard activeID == backupID else { throw RestoreError.recoveryRequired }
                        }
                    } else if let activeID {
                        guard suffix.isEmpty && activeID == record.candidateID else { throw RestoreError.recoveryRequired }
                        try root.remove(name, identity: activeID)
                    }
                }
                if key != record.originalKey { try await keyStore.replaceKey(record.originalKey) }
                guard try await keyStore.loadKey() == record.originalKey else { throw RestoreError.recoveryRequired }
                try recoveryFault(.keyRestored)
            }
            try finish(record, directory: directory, journal: journal, recovering: true)
        })
    }

    public func discard(_ candidate: RestoreCandidate) throws {
        let root = try RestoreDirectory(activeStoreURL.deletingLastPathComponent())
        guard try root.info(journalURL.lastPathComponent) == nil else { throw RestoreError.recoveryRequired }
        let directory = try checkedCandidate(candidate, root: root)
        try cleanupCandidate(directory, root: root, identity: candidate.databaseID)
    }

    private func checkedCandidate(_ candidate: RestoreCandidate, root: RestoreDirectory) throws -> RestoreDirectory {
        guard candidate.directory.deletingLastPathComponent() == root.url,
              candidate.databaseURL == candidate.directory.appendingPathComponent("candidate.sqlite") else { throw RestoreError.invalidCandidate }
        let directory = try RestoreDirectory(candidate.directory, privateOnly: true)
        guard directory.identity == candidate.directoryID else { throw RestoreError.invalidCandidate }
        try directory.require("candidate.sqlite", candidate.databaseID)
        for suffix in Self.suffixes.dropFirst() {
            guard try directory.info("candidate.sqlite" + suffix) == nil else { throw RestoreError.invalidCandidate }
        }
        let file = try directory.file("candidate.sqlite"); defer { try? file.close() }
        guard try digest(file) == candidate.digest else { throw RestoreError.invalidCandidate }
        return directory
    }

    private func digest(_ file: FileHandle) throws -> Data {
        try file.seek(toOffset: 0)
        var hash = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return Data(hash.finalize())
    }

    private func finish(_ record: RestoreRecord, directory: RestoreDirectory, journal: RestoreJournal, recovering: Bool = false) throws {
        // Keep the recovery marker until every known artifact is cleaned. Both
        // rollback and committed cleanup tolerate already-moved/deleted files.
        for (suffix, identity) in record.backupIDs where try directory.info("original.sqlite" + suffix) != nil {
            try directory.remove("original.sqlite" + suffix, identity: identity)
        }
        for (suffix, identity) in record.originalIDs where try directory.info("displaced.sqlite" + suffix) != nil {
            try directory.remove("displaced.sqlite" + suffix, identity: identity)
        }
        if try directory.info("candidate.sqlite") != nil { try directory.remove("candidate.sqlite", identity: record.candidateID) }
        try removeDirectory(directory, root: journal.root)
        if recovering { try recoveryFault(.directoryRemoved) }
        try journal.remove()
    }

    private func cleanupCandidate(_ directory: RestoreDirectory, root: RestoreDirectory, identity: RestoreFileID) throws {
        try directory.check()
        // A substituted file is never ours to unlink. SQLite owns its temporary
        // sidecars; unknown children make rmdir fail safely, without recursion.
        if try directory.info("candidate.sqlite") != nil { try directory.remove("candidate.sqlite", identity: identity) }
        try removeDirectory(directory, root: root)
    }

    private func removeDirectory(_ directory: RestoreDirectory, root: RestoreDirectory) throws {
        guard let value = try root.info(directory.url.lastPathComponent), RestoreFileID(value) == directory.identity else { throw RestoreError.ioFailure }
        guard unlinkat(root.fd, directory.url.lastPathComponent, AT_REMOVEDIR) == 0 else { throw RestoreError.ioFailure }
        try root.sync()
    }
}
