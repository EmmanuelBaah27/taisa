import Foundation

public struct SnapshotManifest: Codable, Equatable, Sendable {
    public let formatVersion: Int
    public let schemaVersion: Int
    public let createdAt: Date
    public let sourceInstallationID: UUID
    /// Plaintext of the outer frames is an independently encrypted SQLCipher file.
    public let plaintextByteCount: Int64
    public let plaintextSHA256: Data
    public let entityCounts: [String: Int]
    public let chunkCount: Int
}

public protocol AudioExportGuard: Sendable {
    /// Must fail while unfinished work depends on audio files. The caller owns
    /// serialization with audio capture/submission for the whole export operation.
    func assertNoPendingAudioReferences() async throws
}

public struct SnapshotReceipt: Equatable, Sendable {
    public let archiveURL: URL
    public let manifest: SnapshotManifest
}

public enum SnapshotError: String, Error, Equatable, Sendable, CustomStringConvertible {
    case pendingAudio
    case authenticationFailed
    case malformedArchive
    case unsupportedVersion
    case insufficientCapacity
    case destinationExists
    case ioFailure
    case checkpointFailed

    public var description: String { rawValue }
}

public struct SnapshotCapacityPolicy: Sendable {
    public let maximumDatabaseBytes: Int64
    public let minimumFreeBytes: Int64
    public init(maximumDatabaseBytes: Int64 = 1_073_741_824, minimumFreeBytes: Int64 = 16_777_216) {
        self.maximumDatabaseBytes = maximumDatabaseBytes
        self.minimumFreeBytes = minimumFreeBytes
    }

    func check(databaseBytes: Int64, directory: URL) throws {
        guard databaseBytes > 0, maximumDatabaseBytes > 0,
              databaseBytes <= maximumDatabaseBytes, minimumFreeBytes >= 0,
              databaseBytes <= (Int64.max - minimumFreeBytes) / 3 else {
            throw SnapshotError.insufficientCapacity
        }
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: directory.path)
        guard let available = attributes[.systemFreeSize] as? NSNumber,
              available.int64Value >= databaseBytes * 3 + minimumFreeBytes else {
            throw SnapshotError.insufficientCapacity
        }
    }
}
