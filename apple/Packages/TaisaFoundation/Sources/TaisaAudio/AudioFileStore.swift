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
}
