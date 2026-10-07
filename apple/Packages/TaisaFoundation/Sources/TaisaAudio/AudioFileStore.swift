import CryptoKit
import Foundation

public struct PendingAudioFile: Sendable, Equatable {
    public let turnID: UUID
    public let fileID: UUID
    public let url: URL

    public init(turnID: UUID, fileID: UUID, url: URL) {
        self.turnID = turnID
        self.fileID = fileID
        self.url = url
    }
}

public struct FinalizedAudio: Sendable, Equatable {
    public let fileID: UUID
    public let url: URL
    public let duration: TimeInterval
    public let byteCount: Int64
    public let sha256: String

    public init(fileID: UUID, url: URL, duration: TimeInterval, byteCount: Int64, sha256: String) {
        self.fileID = fileID
        self.url = url
        self.duration = duration
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

public protocol AudioFileStoring: Sendable {
    func allocate(turnID: UUID) async throws -> PendingAudioFile
    func finalize(_ pending: PendingAudioFile, duration: TimeInterval) async throws -> FinalizedAudio
    func delete(_ pending: PendingAudioFile) async throws
    func load(turnID: UUID, fileID: UUID, duration: TimeInterval) async throws -> FinalizedAudio
    func delete(fileID: UUID) async throws
}

public actor ProtectedAudioFileStore: AudioFileStoring {
    private let directory: URL
    private let fileManager: FileManager

    public init(directory: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        if let directory {
            self.directory = directory
        } else {
            self.directory = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("Taisa/Audio", isDirectory: true)
        }
        try fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
        try Self.excludeFromBackup(self.directory)
        #if os(iOS)
        try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: self.directory.path)
        #endif
    }

    public func allocate(turnID: UUID) async throws -> PendingAudioFile {
        let fileID = UUID()
        let url = directory.appendingPathComponent("\(turnID.uuidString)-\(fileID.uuidString).m4a")
        return PendingAudioFile(turnID: turnID, fileID: fileID, url: url)
    }

    public func finalize(_ pending: PendingAudioFile, duration: TimeInterval) async throws -> FinalizedAudio {
        let attributes = try fileManager.attributesOfItem(atPath: pending.url.path)
        let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard bytes > 0 else { throw AudioCaptureError.audioNotFinalized }
        #if os(iOS)
        try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: pending.url.path)
        #endif
        try Self.excludeFromBackup(pending.url)
        return FinalizedAudio(
            fileID: pending.fileID,
            url: pending.url,
            duration: duration,
            byteCount: bytes,
            sha256: try hash(at: pending.url)
        )
    }

    public func delete(_ pending: PendingAudioFile) async throws {
        guard fileManager.fileExists(atPath: pending.url.path) else { return }
        try fileManager.removeItem(at: pending.url)
    }

    public func load(
        turnID: UUID,
        fileID: UUID,
        duration: TimeInterval
    ) async throws -> FinalizedAudio {
        let url = fileURL(turnID: turnID, fileID: fileID)
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard bytes > 0, duration >= 0 else { throw AudioCaptureError.audioNotFinalized }
        return FinalizedAudio(
            fileID: fileID, url: url, duration: duration,
            byteCount: bytes, sha256: try hash(at: url)
        )
    }

    public func delete(fileID: UUID) async throws {
        let suffix = "-\(fileID.uuidString).m4a"
        let matches = try fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ).filter { $0.lastPathComponent.hasSuffix(suffix) }
        guard matches.count <= 1 else { throw AudioCaptureError.invalidState }
        if let url = matches.first { try fileManager.removeItem(at: url) }
    }

    private func fileURL(turnID: UUID, fileID: UUID) -> URL {
        directory.appendingPathComponent("\(turnID.uuidString)-\(fileID.uuidString).m4a")
    }

    private func hash(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
            guard !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }
}
