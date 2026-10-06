import Foundation
import Darwin
import TaisaRecovery
import TaisaSecurity
import TaisaStorage

/// Owns private transfer files and opaque validated candidates. The screen never
/// receives database keys, candidate paths, manifests or user content.
actor PersonalRecoveryBackend {
    private let storeURL: URL
    private let keyStore: any DatabaseKeyStore
    private let installationID: UUID
    private let transferRoot: URL
    private let audioGuard: any AudioExportGuard
    private var transferDirectory: URL?
    private var transferLock: Int32?
    private var importedArchive: URL?
    private var candidate: RestoreCandidate?
    private var coordinator: RestoreCoordinator { .init(activeStoreURL: storeURL, keyStore: keyStore) }

    init(storeURL: URL, keyStore: any DatabaseKeyStore, installationID: UUID,
         transferRoot: URL, audioGuard: any AudioExportGuard) {
        self.storeURL = storeURL; self.keyStore = keyStore; self.installationID = installationID
        self.transferRoot = transferRoot; self.audioGuard = audioGuard
    }

    deinit { if let transferLock { Darwin.close(transferLock) } }

    static func personal() throws -> PersonalRecoveryBackend {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true).appendingPathComponent("Taisa", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.complete])
        var protectedRoot = root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try protectedRoot.setResourceValues(values)
        let defaults = UserDefaults.standard
        let id = defaults.string(forKey: "taisa.personal.installation").flatMap(UUID.init(uuidString:)) ?? UUID()
        defaults.set(id.uuidString, forKey: "taisa.personal.installation")
        return .init(storeURL: root.appendingPathComponent("taisa.sqlite"), keyStore: KeychainStore(),
                     installationID: id, transferRoot: FileManager.default.temporaryDirectory.appendingPathComponent("TaisaTransfers"),
                     audioGuard: FoundationAudioGuard())
    }

    func openStore() async throws -> TaisaStore {
        try await coordinator.recoverInterruptedPromotion()
        try sweepAbandonedTransfers()
        return try await TaisaStore.open(at: storeURL, keyStore: keyStore)
    }

    func createBackup(key: RecoveryKey) async throws -> TaisaBackupDocument {
        let directory = try makeTransferDirectory()
        do {
            let store = try await openStore()
            let receipt = try await SnapshotService(store: store, audioGuard: audioGuard,
                sourceInstallationID: installationID).createPortableArchive(
                    at: directory.appendingPathComponent("Taisa.taisa-backup"), recoveryKey: key)
            try Task.checkCancellation()
            return try TaisaBackupDocument(verified: receipt, recoveryKey: key)
        } catch { try? cleanup(); throw error }
    }

    func copyImport(_ source: URL) throws {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        guard source.isFileURL else { throw SnapshotError.ioFailure }
        let directory = try makeTransferDirectory()
        let destination = directory.appendingPathComponent("import.taisa-backup")
        do {
            // File providers may require coordinated reads. Never validate or retain
            // the provider URL after the security-scoped access ends.
            var coordinationError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
                do {
                    let descriptor = Darwin.open(readable.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
                    guard descriptor >= 0 else { throw SnapshotError.ioFailure }
                    let input = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                    defer { try? input.close() }
                    var info = stat()
                    guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
                          info.st_size > 0, info.st_size <= 1_100_000_000 else { throw SnapshotError.malformedArchive }
                    let outputFD = Darwin.open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
                    guard outputFD >= 0 else { throw SnapshotError.ioFailure }
                    let output = FileHandle(fileDescriptor: outputFD, closeOnDealloc: true)
                    defer { try? output.close() }
                    var count = 0
                    while let bytes = try input.read(upToCount: 1_048_576), !bytes.isEmpty {
                        try Task.checkCancellation()
                        count += bytes.count
                        guard count <= 1_100_000_000 else { throw SnapshotError.malformedArchive }
                        try output.write(contentsOf: bytes)
                    }
                    guard count == info.st_size else { throw SnapshotError.malformedArchive }
                    try output.synchronize()
                } catch { copyError = error }
            }
            if coordinationError != nil || copyError != nil { throw SnapshotError.ioFailure }
            importedArchive = destination
        } catch { try? cleanup(); throw error }
    }

    func validate(key: RecoveryKey) async throws {
        guard let importedArchive else { throw SnapshotError.ioFailure }
        _ = try await openStore()
        candidate = try await coordinator.validate(archiveURL: importedArchive, recoveryKey: key)
    }

    func promote(confirmed: Bool) async throws {
        guard confirmed, let candidate else { throw RestoreError.declined }
        // The coordinator now owns cleanup/rollback (or a retained journal).
        // Do not later discard a candidate already consumed by promotion.
        self.candidate = nil
        do {
            _ = try await coordinator.promote(candidate, confirmReplacement: { confirmed })
            _ = try await openStore()
        } catch {
            // A failed restore may have closed all prior handles. Recovery/open
            // must settle before any later operation; retained journal is sacred.
            _ = try? await openStore()
            throw error
        }
    }

    func cleanup() throws {
        if let candidate {
            try coordinator.discard(candidate)
            self.candidate = nil
        }
        importedArchive = nil
        if let transferDirectory {
            try FileManager.default.removeItem(at: transferDirectory)
            self.transferDirectory = nil
            if let transferLock { Darwin.close(transferLock); self.transferLock = nil }
        }
    }

    private func makeTransferDirectory() throws -> URL {
        guard transferDirectory == nil else { throw SnapshotError.ioFailure }
        try FileManager.default.createDirectory(at: transferRoot, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.complete])
        let directory = transferRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.complete])
        transferDirectory = directory
        let lock = Darwin.open(directory.appendingPathComponent(".owner").path,
                               O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw SnapshotError.ioFailure }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { Darwin.close(lock); throw SnapshotError.ioFailure }
        transferLock = lock
        return directory
    }
    /// Only our marked transfer namespace is eligible. A live lease is held by
    /// flock for the entire backend/export lifetime and released by process death.
    /// Restore candidates and journals live elsewhere and are never traversed.
    private func sweepAbandonedTransfers() throws {
        let rootFD = Darwin.open(transferRoot.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if rootFD < 0, errno == ENOENT { return }
        guard rootFD >= 0 else { throw SnapshotError.ioFailure }
        defer { Darwin.close(rootFD) }
        var rootInfo = stat()
        guard fstat(rootFD, &rootInfo) == 0, rootInfo.st_uid == geteuid(), rootInfo.st_mode & 0o777 == 0o700 else {
            throw SnapshotError.ioFailure
        }
        for name in try FileManager.default.contentsOfDirectory(atPath: transferRoot.path) where UUID(uuidString: name) != nil {
            let directoryFD = openat(rootFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard directoryFD >= 0 else { continue }
            defer { Darwin.close(directoryFD) }
            var directoryInfo = stat()
            guard fstat(directoryFD, &directoryInfo) == 0, directoryInfo.st_uid == geteuid(),
                  directoryInfo.st_mode & 0o777 == 0o700 else { continue }
            let owner = openat(directoryFD, ".owner", O_RDWR | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard owner >= 0 else { continue }
            defer { Darwin.close(owner) }
            var ownerInfo = stat()
            guard fstat(owner, &ownerInfo) == 0, ownerInfo.st_mode & S_IFMT == S_IFREG,
                  ownerInfo.st_uid == geteuid(), ownerInfo.st_nlink == 1,
                  flock(owner, LOCK_EX | LOCK_NB) == 0 else { continue }
            let url = transferRoot.appendingPathComponent(name)
            guard try removeKnownTransferContents(at: url, descriptor: directoryFD) else { continue }
            var current = stat()
            if fstatat(rootFD, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
               sameIdentity(directoryInfo, current) { _ = unlinkat(rootFD, name, AT_REMOVEDIR) }
        }
    }

    private func removeKnownTransferContents(at url: URL, descriptor: Int32, staging: Bool = false) throws -> Bool {
        let names = try FileManager.default.contentsOfDirectory(atPath: url.path)
        let allowed = staging ? ["checkpoint.sqlite", "checkpoint.sqlite-wal", "checkpoint.sqlite-shm", "checkpoint.sqlite-journal", "archive.partial"]
                              : [".owner", "Taisa.taisa-backup", "import.taisa-backup"]
        var files: [(String, stat)] = []
        var directories: [(String, stat)] = []
        // Unknown content, links, nonregular files and substituted inodes fail closed.
        for name in names {
            var info = stat()
            guard fstatat(descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0, info.st_uid == geteuid() else { return false }
            if allowed.contains(name), info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 {
                files.append((name, info))
            } else if !staging, name.hasPrefix(".taisa-"), UUID(uuidString: String(name.dropFirst(7))) != nil,
                      info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o777 == 0o700 {
                directories.append((name, info))
            } else { return false }
        }
        for (name, identity) in directories {
            let child = openat(descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard child >= 0 else { return false }
            defer { Darwin.close(child) }
            var actual = stat()
            guard fstat(child, &actual) == 0, sameIdentity(identity, actual),
                  try removeKnownTransferContents(at: url.appendingPathComponent(name), descriptor: child, staging: true),
                  fstatat(descriptor, name, &actual, AT_SYMLINK_NOFOLLOW) == 0, sameIdentity(identity, actual),
                  unlinkat(descriptor, name, AT_REMOVEDIR) == 0 else { return false }
        }
        // The marker is removed last, while its lock is still held.
        for (name, identity) in files.sorted(by: { $0.0 != ".owner" && $1.0 == ".owner" }) {
            var actual = stat()
            guard fstatat(descriptor, name, &actual, AT_SYMLINK_NOFOLLOW) == 0, sameIdentity(identity, actual),
                  unlinkat(descriptor, name, 0) == 0 else { return false }
        }
        return true
    }

    private func sameIdentity(_ first: stat, _ second: stat) -> Bool {
        first.st_dev == second.st_dev && first.st_ino == second.st_ino && first.st_mode & S_IFMT == second.st_mode & S_IFMT
    }
}

/// This foundation app has no audio capture/submission feature. Keep the guard
/// explicit: adding such a feature must replace this with its serialized owner.
private struct FoundationAudioGuard: AudioExportGuard {
    func assertNoPendingAudioReferences() async throws { try Task.checkCancellation() }
}
