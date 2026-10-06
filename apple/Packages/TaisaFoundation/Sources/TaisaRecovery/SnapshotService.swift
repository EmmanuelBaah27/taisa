import Darwin
import Foundation
import GRDB
import TaisaSecurity
import TaisaStorage

public struct SnapshotService: Sendable {
    private let store: TaisaStore
    private let audioGuard: any AudioExportGuard
    private let sourceInstallationID: UUID
    private let clock: @Sendable () -> Date
    private let capacityPolicy: SnapshotCapacityPolicy
    private let beforeVerification: @Sendable (URL) throws -> Void

    public init(store: TaisaStore, audioGuard: any AudioExportGuard, sourceInstallationID: UUID,
                clock: @escaping @Sendable () -> Date = { Date() },
                capacityPolicy: SnapshotCapacityPolicy = .init()) {
        self.init(store: store, audioGuard: audioGuard, sourceInstallationID: sourceInstallationID,
                  clock: clock, capacityPolicy: capacityPolicy, beforeVerification: { _ in })
    }

    // Deterministic I/O fault boundary, analogous to TaisaStore's validation handoff.
    init(store: TaisaStore, audioGuard: any AudioExportGuard, sourceInstallationID: UUID,
         clock: @escaping @Sendable () -> Date = { Date() },
         capacityPolicy: SnapshotCapacityPolicy = .init(),
         beforeVerification: @escaping @Sendable (URL) throws -> Void) {
        self.store = store; self.audioGuard = audioGuard; self.sourceInstallationID = sourceInstallationID
        self.clock = clock; self.capacityPolicy = capacityPolicy; self.beforeVerification = beforeVerification
    }

    public func createPortableArchive(at destination: URL, recoveryKey: RecoveryKey) async throws -> SnapshotReceipt {
        try Task.checkCancellation()
        // No destination or staging artifact may exist before this guard succeeds.
        do { try await audioGuard.assertNoPendingAudioReferences() }
        catch is CancellationError { throw CancellationError() }
        catch { throw SnapshotError.pendingAudio }
        let directory = destination.deletingLastPathComponent()
        let staging = directory.appendingPathComponent(".taisa-\(UUID().uuidString)", isDirectory: true)
        let temporaryArchive = staging.appendingPathComponent("archive.partial")
        do {
            guard destination.isFileURL else { throw SnapshotError.ioFailure }
            guard !FileManager.default.fileExists(atPath: destination.path) else { throw SnapshotError.destinationExists }
            let parentFD = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard parentFD >= 0 else { throw SnapshotError.ioFailure }
            defer { Darwin.close(parentFD) }
            let parentIdentity = try ArchiveFileIdentity(descriptor: parentFD)
            // Preflight uses page_count, not a partial main-file size while WAL is live.
            let estimatedBytes = try await store.read { db in
                let pages = try Int64.fetchOne(db, sql: "PRAGMA page_count") ?? 0
                let pageSize = try Int64.fetchOne(db, sql: "PRAGMA page_size") ?? 0
                let value = pages.multipliedReportingOverflow(by: pageSize)
                guard !value.overflow else { throw SnapshotError.insufficientCapacity }
                return value.partialValue
            }
            try capacityPolicy.check(databaseBytes: estimatedBytes, directory: directory)
            guard mkdirat(parentFD, staging.lastPathComponent, 0o700) == 0 else { throw SnapshotError.ioFailure }
            let stagingFD = openat(parentFD, staging.lastPathComponent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard stagingFD >= 0 else { throw SnapshotError.ioFailure }
            defer { Darwin.close(stagingFD) }
            let stagingIdentity = try ArchiveFileIdentity(descriptor: stagingFD)
            var ownedFiles: [String: ArchiveFileIdentity] = [:]
            // Descriptor-relative cleanup never follows a replaced parent path,
            // never recurses into substitute directories, and only unlinks our inodes.
            defer {
                for (name, identity) in ownedFiles {
                    if identity.matches(directory: stagingFD, name: name) {
                        unlinkat(stagingFD, name, 0)
                    }
                }
                if stagingIdentity.matches(directory: parentFD, name: staging.lastPathComponent) {
                    unlinkat(parentFD, staging.lastPathComponent, AT_REMOVEDIR)
                }
            }
            try parentIdentity.requirePath(directory)
            try stagingIdentity.requirePrivateDirectory(descriptor: stagingFD)
            let database = staging.appendingPathComponent("checkpoint.sqlite")
            let salt = try PortableArchive.randomSalt()
            let databaseKey = try recoveryKey.derivePortableBackupKey(salt: salt, purpose: .database)
            let checkpoint: CheckpointMetadata
            do { checkpoint = try await store.exportCheckpoint(to: database, archiveDatabaseKey: databaseKey.withUnsafeBytes { Data($0) }) }
            catch is CancellationError { throw CancellationError() }
            catch { throw SnapshotError.checkpointFailed }
            ownedFiles[database.lastPathComponent] = try ArchiveFileIdentity(directory: stagingFD, name: database.lastPathComponent)
            try capacityPolicy.check(databaseBytes: checkpoint.plaintextByteCount, directory: directory)
            let chunkCount = (checkpoint.plaintextByteCount - 1) / Int64(PortableArchive.chunkSize) + 1
            guard chunkCount <= Int64(UInt32.max) else { throw SnapshotError.insufficientCapacity }
            let manifest = SnapshotManifest(formatVersion: 1, schemaVersion: checkpoint.schemaVersion,
                createdAt: Date(timeIntervalSince1970: floor(clock().timeIntervalSince1970 * 1_000) / 1_000), sourceInstallationID: sourceInstallationID,
                plaintextByteCount: checkpoint.plaintextByteCount, plaintextSHA256: checkpoint.plaintextSHA256,
                entityCounts: checkpoint.entityCounts, chunkCount: Int(chunkCount))
            let descriptor = openat(stagingFD, temporaryArchive.lastPathComponent, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else { throw SnapshotError.ioFailure }
            let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? output.close() }
            let archiveIdentity = try ArchiveFileIdentity(descriptor: descriptor)
            ownedFiles[temporaryArchive.lastPathComponent] = archiveIdentity
            try PortableArchive.write(database: database, manifest: manifest, salt: salt, recoveryKey: recoveryKey, to: output)
            try output.synchronize()
            try beforeVerification(temporaryArchive)
            try parentIdentity.requirePath(directory)
            try stagingIdentity.requirePath(staging)
            try stagingIdentity.requirePrivateDirectory(descriptor: stagingFD)
            try archiveIdentity.requirePrivateFile(descriptor: descriptor, directory: stagingFD, name: temporaryArchive.lastPathComponent)
            guard try PortableArchive.verify(file: output, recoveryKey: recoveryKey,
                    maximumPayloadBytes: capacityPolicy.maximumDatabaseBytes) == manifest else {
                throw SnapshotError.authenticationFailed
            }
            try Task.checkCancellation()
            try parentIdentity.requirePath(directory)
            try stagingIdentity.requirePath(staging)
            try stagingIdentity.requirePrivateDirectory(descriptor: stagingFD)
            try archiveIdentity.requirePrivateFile(descriptor: descriptor, directory: stagingFD, name: temporaryArchive.lastPathComponent)
            // The source lives in our retained 0700 directory, inaccessible to
            // other users even when the destination directory is shared. Both
            // rename operands are anchored to descriptors, not mutable parents.
            guard renameatx_np(stagingFD, temporaryArchive.lastPathComponent,
                              parentFD, destination.lastPathComponent, UInt32(RENAME_EXCL)) == 0 else {
                throw errno == EEXIST ? SnapshotError.destinationExists : SnapshotError.ioFailure
            }
            do {
                try archiveIdentity.requirePrivateFile(descriptor: descriptor, directory: parentFD, name: destination.lastPathComponent)
                try parentIdentity.requirePath(directory)
            } catch {
                if archiveIdentity.matches(directory: parentFD, name: destination.lastPathComponent) {
                    unlinkat(parentFD, destination.lastPathComponent, 0)
                }
                throw SnapshotError.ioFailure
            }
            return SnapshotReceipt(archiveURL: destination, manifest: manifest)
        } catch is CancellationError { throw CancellationError() }
        catch let error as SnapshotError { throw error }
        catch { throw SnapshotError.ioFailure }
    }
}

/// Identity checks intentionally omit permissions for cleanup: a chmod of our
/// inode may reject publication but never grants ownership of a substitute.
private struct ArchiveFileIdentity {
    let device: dev_t
    let inode: ino_t
    let type: mode_t

    init(descriptor: Int32) throws {
        var value = stat()
        guard fstat(descriptor, &value) == 0 else { throw SnapshotError.ioFailure }
        self.init(value)
    }

    init(directory: Int32, name: String) throws {
        var value = stat()
        guard fstatat(directory, name, &value, AT_SYMLINK_NOFOLLOW) == 0 else { throw SnapshotError.ioFailure }
        self.init(value)
    }

    private init(_ value: stat) {
        device = value.st_dev; inode = value.st_ino; type = value.st_mode & S_IFMT
    }

    private func matches(_ value: stat) -> Bool {
        value.st_dev == device && value.st_ino == inode && value.st_mode & S_IFMT == type
    }

    func matches(directory: Int32, name: String) -> Bool {
        var value = stat()
        return fstatat(directory, name, &value, AT_SYMLINK_NOFOLLOW) == 0 && matches(value)
    }

    func requirePath(_ url: URL) throws {
        var value = stat()
        guard lstat(url.path, &value) == 0, matches(value) else { throw SnapshotError.ioFailure }
    }

    func requirePrivateDirectory(descriptor: Int32) throws {
        var value = stat()
        guard fstat(descriptor, &value) == 0, matches(value), type == S_IFDIR,
              value.st_mode & 0o7777 == 0o700, value.st_uid == geteuid() else { throw SnapshotError.ioFailure }
    }

    func requirePrivateFile(descriptor: Int32, directory: Int32, name: String) throws {
        var value = stat()
        guard fstat(descriptor, &value) == 0, matches(value), type == S_IFREG,
              value.st_mode & 0o7777 == 0o600, value.st_nlink == 1,
              value.st_uid == geteuid(), matches(directory: directory, name: name) else {
            throw SnapshotError.ioFailure
        }
    }
}
