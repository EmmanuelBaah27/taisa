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
    private var importedArchive: URL?
    private var candidate: RestoreCandidate?
    private var coordinator: RestoreCoordinator { .init(activeStoreURL: storeURL, keyStore: keyStore) }

    init(storeURL: URL, keyStore: any DatabaseKeyStore, installationID: UUID,
         transferRoot: URL, audioGuard: any AudioExportGuard) {
        self.storeURL = storeURL; self.keyStore = keyStore; self.installationID = installationID
        self.transferRoot = transferRoot; self.audioGuard = audioGuard
    }

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
        return directory
    }
}

/// This foundation app has no audio capture/submission feature. Keep the guard
/// explicit: adding such a feature must replace this with its serialized owner.
private struct FoundationAudioGuard: AudioExportGuard {
    func assertNoPendingAudioReferences() async throws { try Task.checkCancellation() }
}
