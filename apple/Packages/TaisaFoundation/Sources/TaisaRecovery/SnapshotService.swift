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
        let temporaryArchive = directory.appendingPathComponent(".taisa-\(UUID().uuidString).partial")
        var ownsStaging = false
        var ownsArchive = false
        defer {
            if ownsStaging { try? FileManager.default.removeItem(at: staging) }
            if ownsArchive { try? FileManager.default.removeItem(at: temporaryArchive) }
        }
        do {
            guard destination.isFileURL else { throw SnapshotError.ioFailure }
            guard !FileManager.default.fileExists(atPath: destination.path) else { throw SnapshotError.destinationExists }
            // Preflight uses page_count, not a partial main-file size while WAL is live.
            let estimatedBytes = try await store.read { db in
                let pages = try Int64.fetchOne(db, sql: "PRAGMA page_count") ?? 0
                let pageSize = try Int64.fetchOne(db, sql: "PRAGMA page_size") ?? 0
                let value = pages.multipliedReportingOverflow(by: pageSize)
                guard !value.overflow else { throw SnapshotError.insufficientCapacity }
                return value.partialValue
            }
            try capacityPolicy.check(databaseBytes: estimatedBytes, directory: directory)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            ownsStaging = true
            let database = staging.appendingPathComponent("checkpoint.sqlite")
            let salt = try PortableArchive.randomSalt()
            let databaseKey = try recoveryKey.derivePortableBackupKey(salt: salt, purpose: .database)
            let checkpoint: CheckpointMetadata
            do { checkpoint = try await store.exportCheckpoint(to: database, archiveDatabaseKey: databaseKey.withUnsafeBytes { Data($0) }) }
            catch is CancellationError { throw CancellationError() }
            catch { throw SnapshotError.checkpointFailed }
            try capacityPolicy.check(databaseBytes: checkpoint.plaintextByteCount, directory: directory)
            let chunkCount = (checkpoint.plaintextByteCount - 1) / Int64(PortableArchive.chunkSize) + 1
            guard chunkCount <= Int64(UInt32.max) else { throw SnapshotError.insufficientCapacity }
            let manifest = SnapshotManifest(formatVersion: 1, schemaVersion: checkpoint.schemaVersion,
                createdAt: Date(timeIntervalSince1970: floor(clock().timeIntervalSince1970 * 1_000) / 1_000), sourceInstallationID: sourceInstallationID,
                plaintextByteCount: checkpoint.plaintextByteCount, plaintextSHA256: checkpoint.plaintextSHA256,
                entityCounts: checkpoint.entityCounts, chunkCount: Int(chunkCount))
            let descriptor = Darwin.open(temporaryArchive.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else { throw SnapshotError.ioFailure }
            ownsArchive = true
            let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? output.close() }
            try PortableArchive.write(database: database, manifest: manifest, salt: salt, recoveryKey: recoveryKey, to: output)
            try output.synchronize()
            try output.close()
            try beforeVerification(temporaryArchive)
            guard try PortableArchive.verify(at: temporaryArchive, recoveryKey: recoveryKey,
                    maximumPayloadBytes: capacityPolicy.maximumDatabaseBytes) == manifest else {
                throw SnapshotError.authenticationFailed
            }
            try Task.checkCancellation()
            // Darwin's exclusive rename is atomic and never overwrites a destination
            // that appeared after the preflight check.
            guard renamex_np(temporaryArchive.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
                throw errno == EEXIST ? SnapshotError.destinationExists : SnapshotError.ioFailure
            }
            ownsArchive = false
            return SnapshotReceipt(archiveURL: destination, manifest: manifest)
        } catch is CancellationError { throw CancellationError() }
        catch let error as SnapshotError { throw error }
        catch { throw SnapshotError.ioFailure }
    }
}
