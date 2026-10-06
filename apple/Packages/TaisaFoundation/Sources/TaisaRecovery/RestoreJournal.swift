import CryptoKit
import Darwin
import Foundation

public enum RestorePhase: String, Codable, Sendable {
    case prepared, originalMoved, candidateMoved, keyCommitted, committed
}

public enum RestoreError: String, Error, Sendable, CustomStringConvertible {
    case insufficientCapacity, declined, invalidCandidate, recoveryRequired, ioFailure, keyFailure, incompatibleSchema
    public var description: String { rawValue }
}

// Internal deterministic interruption boundary. Production initializers cannot
// install this hook. An interruption deliberately bypasses in-process rollback.
enum RestoreInterruption: Error { case simulatedCrash }
enum RestoreFaultPoint: String, CaseIterable, Sendable {
    case prepared, originalMoveBeforeJournal, originalMoved, candidateMoveBeforeJournal
    case candidateMoved, keySaveBeforeJournal, keyCommitted, committed
}
enum RestoreRecoveryFaultPoint: String, CaseIterable, Sendable {
    case databaseRestored, walRestored, sharedMemoryRestored, keyRestored, directoryRemoved
}

struct RestoreFileID: Codable, Equatable, Sendable {
    let device: Int64
    let inode: UInt64
    let type: UInt32
    init(_ value: stat) {
        device = Int64(value.st_dev); inode = UInt64(value.st_ino); type = UInt32(value.st_mode & S_IFMT)
    }
}

/// Every operation is relative to retained directory descriptors. No recursive
/// deletion, following symlinks, or replacing a file with an unknown identity.
final class RestoreDirectory: @unchecked Sendable {
    let url: URL
    let fd: Int32
    let identity: RestoreFileID

    init(_ url: URL, privateOnly: Bool = false) throws {
        guard url.isFileURL else { throw RestoreError.ioFailure }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw RestoreError.ioFailure }
        var value = stat()
        guard fstat(descriptor, &value) == 0, value.st_uid == geteuid(),
              value.st_mode & 0o022 == 0,
              !privateOnly || value.st_mode & 0o7777 == 0o700 else {
            Darwin.close(descriptor); throw RestoreError.ioFailure
        }
        self.url = url; fd = descriptor; identity = RestoreFileID(value)
    }
    deinit { Darwin.close(fd) }

    func check() throws {
        var value = stat()
        guard lstat(url.path, &value) == 0, RestoreFileID(value) == identity,
              value.st_uid == geteuid(), value.st_mode & 0o022 == 0 else { throw RestoreError.ioFailure }
    }
    func info(_ name: String) throws -> stat? {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else { throw RestoreError.ioFailure }
        var value = stat()
        if fstatat(fd, name, &value, AT_SYMLINK_NOFOLLOW) != 0 {
            if errno == ENOENT { return nil }
            throw RestoreError.ioFailure
        }
        return value
    }
    func file(_ name: String, create: Bool = false, privateOnly: Bool = true) throws -> FileHandle {
        try check()
        let flags = create ? O_RDWR | O_CREAT | O_EXCL : O_RDONLY
        let descriptor = openat(fd, name, flags | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw RestoreError.ioFailure }
        var value = stat()
        guard fstat(descriptor, &value) == 0, value.st_mode & S_IFMT == S_IFREG,
              value.st_nlink == 1, value.st_uid == geteuid(),
              value.st_mode & 0o022 == 0, !privateOnly || value.st_mode & 0o077 == 0 else {
            Darwin.close(descriptor); throw RestoreError.ioFailure
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }
    func require(_ name: String, _ identity: RestoreFileID) throws {
        guard let value = try info(name), RestoreFileID(value) == identity,
              value.st_uid == geteuid(), value.st_nlink == 1,
              value.st_mode & 0o022 == 0, identity.type == UInt32(S_IFREG) else { throw RestoreError.ioFailure }
    }
    func sync() throws { guard fsync(fd) == 0 else { throw RestoreError.ioFailure } }
    func move(_ name: String, to other: RestoreDirectory, as destination: String, identity: RestoreFileID) throws {
        try check(); try other.check(); try require(name, identity)
        guard renameatx_np(fd, name, other.fd, destination, UInt32(RENAME_EXCL)) == 0 else { throw RestoreError.ioFailure }
        try sync(); try other.sync()
        try other.require(destination, identity)
    }
    func remove(_ name: String, identity: RestoreFileID) throws {
        try require(name, identity)
        guard unlinkat(fd, name, 0) == 0 else { throw RestoreError.ioFailure }
        try sync()
    }
    func copy(_ name: String, identity sourceID: RestoreFileID, to destination: RestoreDirectory, as target: String) throws -> RestoreFileID {
        let input = try file(name, privateOnly: false); defer { try? input.close() }
        var source = stat()
        guard fstat(input.fileDescriptor, &source) == 0, RestoreFileID(source) == sourceID else { throw RestoreError.ioFailure }
        try require(name, sourceID)
        let output = try destination.file(target, create: true); defer { try? output.close() }
        guard let created = try destination.info(target) else { throw RestoreError.ioFailure }
        let identity = RestoreFileID(created)
        var complete = false
        defer { if !complete { try? destination.remove(target, identity: identity) } }
        while let bytes = try input.read(upToCount: 1_048_576), !bytes.isEmpty { try output.write(contentsOf: bytes) }
        try output.synchronize(); try destination.sync()
        try require(name, sourceID)
        try destination.require(target, identity)
        complete = true
        return identity
    }
}

struct RestoreRecord: Codable, Sendable {
    var phase: RestorePhase
    let directoryName: String
    let directoryID: RestoreFileID
    let candidateID: RestoreFileID
    let originalIDs: [String: RestoreFileID]
    let backupIDs: [String: RestoreFileID]
    let originalKey: Data
    let candidateKey: Data
}

/// The journal is sealed twice: once for the old Keychain key, once for the new.
/// At every atomic Keychain update boundary either key opens the same record.
/// No database key is stored as plaintext, including in temp files or errors.
final class RestoreJournal: @unchecked Sendable {
    let root: RestoreDirectory
    let name: String
    // Access is serialized by the active store lifecycle. Tracks the exact
    // inode read/written by this transaction, never ownership by filename.
    private var identity: RestoreFileID?
    init(root: RestoreDirectory, name: String) { self.root = root; self.name = name }
    private struct Envelope: Codable { let old: Data; let new: Data }
    private var aad: Data { Data(("taisa.restore-journal.v1:" + root.url.path + "/" + name).utf8) }

    func write(_ record: RestoreRecord) throws {
        let plain = try JSONEncoder().encode(record)
        let old = try AES.GCM.seal(plain, using: SymmetricKey(data: record.originalKey), authenticating: aad).combined!
        let new = try AES.GCM.seal(plain, using: SymmetricKey(data: record.candidateKey), authenticating: aad).combined!
        let bytes = try JSONEncoder().encode(Envelope(old: old, new: new))
        let temporary = name + "." + UUID().uuidString
        let output = try root.file(temporary, create: true)
        defer { try? output.close() }
        let tempID = try root.info(temporary).map(RestoreFileID.init)
        defer { if let tempID, (try? root.info(temporary).map(RestoreFileID.init)) == tempID { try? root.remove(temporary, identity: tempID) } }
        try output.write(contentsOf: bytes); try output.synchronize()
        try root.check()
        // Refuse links or files not owned privately before replacing an older journal.
        if try root.info(name) != nil {
            guard let identity else { throw RestoreError.recoveryRequired }
            try root.require(name, identity)
        } else if identity != nil { throw RestoreError.recoveryRequired }
        guard renameat(root.fd, temporary, root.fd, name) == 0 else { throw RestoreError.ioFailure }
        identity = tempID
        try root.sync()
    }

    func read(key: Data) throws -> RestoreRecord? {
        guard let value = try root.info(name) else { return nil }
        let readIdentity = RestoreFileID(value)
        if let identity, identity != readIdentity { throw RestoreError.recoveryRequired }
        let file = try root.file(name); defer { try? file.close() }
        // Bound journal parsing even if local input is corrupt.
        guard let bytes = try file.read(upToCount: 65_537), bytes.count <= 65_536 else { throw RestoreError.recoveryRequired }
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: bytes)
            for sealed in [envelope.old, envelope.new] {
                if let plain = try? AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: SymmetricKey(data: key), authenticating: aad),
                   let record = try? JSONDecoder().decode(RestoreRecord.self, from: plain),
                   record.originalKey.count == 32, record.candidateKey.count == 32,
                   record.directoryName.hasPrefix(".taisa-restore-"),
                   !record.directoryName.contains("/") {
                    try root.require(name, readIdentity)
                    identity = readIdentity
                    return record
                }
            }
        } catch { throw RestoreError.recoveryRequired }
        throw RestoreError.recoveryRequired
    }

    func remove() throws {
        if try root.info(name) != nil {
            guard let identity else { throw RestoreError.recoveryRequired }
            try root.remove(name, identity: identity)
        }
    }
}
