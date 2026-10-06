import CryptoKit
import Foundation
import GRDB
import Testing
import TaisaSecurity
@testable import TaisaStorage
@testable import TaisaRecovery

private struct Keys: DatabaseKeyStore {
    let key = Data(repeating: 0x51, count: 32)
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws {}
}

private struct AudioGuard: AudioExportGuard {
    var pending = false
    func assertNoPendingAudioReferences() async throws {
        if pending { throw SnapshotError.pendingAudio }
    }
}

private struct Fixture {
    let directory: URL
    let destination: URL
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        destination = directory.appendingPathComponent("backup.taisa-backup")
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
    func store(large: Bool = false) async throws -> TaisaStore {
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("live.sqlite"), keyStore: Keys())
        try await store.write { db in
            try db.execute(sql: "INSERT INTO profile (id, display_name, updated_at_ms) VALUES (?, 'PRIVATE-ARCHIVE-CANARY', 1)", arguments: [UUID().uuidString])
            try db.execute(sql: "INSERT INTO conversations (id, title, created_at_ms, updated_at_ms) VALUES (?, 'Conversation', 1, 1)", arguments: ["00000000-0000-0000-0000-000000000001"])
            try db.execute(sql: "INSERT INTO messages (id, conversation_id, role, body, created_at_ms) VALUES (?, ?, 'user', ?, 1)", arguments: [UUID().uuidString, "00000000-0000-0000-0000-000000000001", large ? String(repeating: "private", count: 400_000) : "Message"])
        }
        return store
    }
    func leftovers() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(".taisa-") }
    }
}

@Suite(.serialized) struct SnapshotTests {
    let installationID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
    let instant = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func checkpointContainsWALRowsWithIndependentKeyAndDeterministicCounts() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = try await fixture.store()
        let checkpoint = fixture.directory.appendingPathComponent("checkpoint.sqlite")
        let key = Data(repeating: 0x72, count: 32)
        let metadata = try await store.exportCheckpoint(to: checkpoint, archiveDatabaseKey: key)
        #expect(metadata.schemaVersion == 1)
        #expect(metadata.entityCounts["profile"] == 1)
        #expect(metadata.entityCounts["messages"] == 1)
        #expect(metadata.entityCounts["conversations"] == 1)
        #expect(metadata.entityCounts["goals"] == 0)
        #expect(metadata.entityCounts.count == 20)
        let bytes = try Data(contentsOf: checkpoint)
        #expect(metadata.plaintextByteCount == bytes.count)
        #expect(metadata.plaintextSHA256 == Data(SHA256.hash(data: bytes)))
        #expect(!bytes.contains(Data("PRIVATE-ARCHIVE-CANARY".utf8)))
        var config = Configuration(); config.readonly = true
        config.prepareDatabase { try $0.usePassphrase(Data(("x'" + key.map { String(format: "%02x", $0) }.joined() + "'").utf8)) }
        let copy = try DatabaseQueue(path: checkpoint.path, configuration: config)
        #expect(try await copy.read { try String.fetchOne($0, sql: "SELECT display_name FROM profile") } == "PRIVATE-ARCHIVE-CANARY")
        #expect(try await copy.read { try String.fetchAll($0, sql: "SELECT name FROM pragma_table_info('messages')") }.contains("audio_uri") == false)
        #expect(try FileManager.default.attributesOfItem(atPath: checkpoint.path)[.posixPermissions] as? Int == 0o600)
        // A backup must not retain the live database key.
        var wrong = Configuration(); wrong.readonly = true
        wrong.prepareDatabase { try $0.usePassphrase(Data(("x'" + String(repeating: "51", count: 32) + "'").utf8)) }
        #expect(throws: Error.self) { let db = try DatabaseQueue(path: checkpoint.path, configuration: wrong); try db.read { _ = try Int.fetchOne($0, sql: "PRAGMA user_version") } }
    }

    @Test func checkpointWaitsForStoreLifecycleOwnership() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = try await fixture.store()
        let pause = CheckpointPause()
        let opening = Task {
            try await TaisaStore.open(at: fixture.directory.appendingPathComponent("live.sqlite"), keyStore: Keys(),
                afterValidation: {}, afterGeneration: { await pause.hold() })
        }
        await pause.waitUntilHeld()
        let destination = fixture.directory.appendingPathComponent("checkpoint.sqlite")
        let export = Task { try await store.exportCheckpoint(to: destination, archiveDatabaseKey: Data(repeating: 0x72, count: 32)) }
        try await Task.sleep(for: .milliseconds(100))
        let appearedWhileLifecycleHeld = FileManager.default.fileExists(atPath: destination.path)
        await pause.release()
        _ = try await opening.value
        let metadata = try await export.value
        #expect(!appearedWhileLifecycleHeld)
        #expect(metadata.entityCounts["messages"] == 1)
    }

    @Test func archiveRoundTripAuthenticatesManifestAndContainsNoPlaintext() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = try await fixture.store(large: true)
        let key = try RecoveryKey.generate()
        let service = SnapshotService(store: store, audioGuard: AudioGuard(), sourceInstallationID: installationID, clock: { instant })
        let receipt = try await service.createPortableArchive(at: fixture.destination, recoveryKey: key)
        let verified = try PortableArchive.verify(at: fixture.destination, recoveryKey: key)
        #expect(receipt.manifest == verified)
        #expect(verified.createdAt == instant)
        #expect(verified.sourceInstallationID == installationID)
        #expect(verified.formatVersion == 1)
        #expect(verified.chunkCount >= 3)
        #expect(verified.entityCounts["messages"] == 1)
        let archive = try Data(contentsOf: fixture.destination)
        #expect(!archive.contains(Data("PRIVATE-ARCHIVE-CANARY".utf8)))
        #expect(!archive.contains(Data(key.formatted.utf8)))
        #expect(!archive.contains(Data("profile".utf8)))
        #expect(try FileManager.default.attributesOfItem(atPath: fixture.destination.path)[.posixPermissions] as? Int == 0o600)
        #expect(try fixture.leftovers().isEmpty)
        let pieces = try split(archive)
        let nonces = [pieces.manifest.prefix(12)] + pieces.frames.map { $0.dropFirst(4).prefix(12) }
        #expect(Set(nonces.map { Data($0) }).count == nonces.count)
        // Independently derive the exact mandated HKDF context and AAD layout.
        let material = Data(key.formatted.split(separator: "-")[1...8].joined().hexBytes)
        let frameKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: material), salt: pieces.header.subdata(in: 28..<60), info: Data("taisa.portable-backup.frames.v1".utf8), outputByteCount: 32)
        let manifestData = try AES.GCM.open(AES.GCM.SealedBox(combined: pieces.manifest), using: frameKey, authenticating: pieces.header)
        let digest = Data(SHA256.hash(data: manifestData))
        var payload = Data()
        for (index, frame) in pieces.frames.enumerated() {
            let aad = pieces.header + digest + u32(index) + u32(pieces.frames.count)
            payload.append(try AES.GCM.open(AES.GCM.SealedBox(combined: Data(frame.dropFirst(4))), using: frameKey, authenticating: aad))
        }
        #expect(Data(SHA256.hash(data: payload)) == verified.plaintextSHA256)
        #expect(payload.count == verified.plaintextByteCount)
        let databaseKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: material), salt: pieces.header.subdata(in: 28..<60), info: Data("taisa.portable-backup.database.v1".utf8), outputByteCount: 32)
        let copyURL = fixture.directory.appendingPathComponent("independent.sqlite")
        try payload.write(to: copyURL)
        var config = Configuration(); config.readonly = true
        let dbKey = databaseKey.withUnsafeBytes { Data($0) }
        config.prepareDatabase { try $0.usePassphrase(Data(("x'" + dbKey.map { String(format: "%02x", $0) }.joined() + "'").utf8)) }
        let copy = try DatabaseQueue(path: copyURL.path, configuration: config)
        #expect(try await copy.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM messages") } == 1)
    }

    @Test func pendingAudioRejectsBeforeAnyDestinationArtifact() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = try await fixture.store()
        let before = try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).sorted()
        let service = SnapshotService(store: store, audioGuard: AudioGuard(pending: true), sourceInstallationID: installationID)
        await #expect(throws: SnapshotError.pendingAudio) { try await service.createPortableArchive(at: fixture.destination, recoveryKey: .generate()) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).sorted() == before)
    }

    @Test func fractionalClockSurvivesCanonicalManifestRoundTrip() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = try await fixture.store()
        let key = try RecoveryKey.generate()
        for tick in 1...20 {
            let now = Date(timeIntervalSinceReferenceDate: 812_345_678 + Double(tick) / 10_000_003)
            let service = SnapshotService(store: store, audioGuard: AudioGuard(), sourceInstallationID: installationID, clock: { now })
            let destination = fixture.directory.appendingPathComponent("\(tick).taisa-backup")
            let receipt = try await service.createPortableArchive(at: destination, recoveryKey: key)
            #expect(abs(receipt.manifest.createdAt.timeIntervalSince(now)) < 0.001)
        }
    }

    @Test func cancellationAndDiskFailureAfterWritingRemoveAllStaging() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = try await fixture.store()
        let key = try RecoveryKey.generate()
        let failing = SnapshotService(store: store, audioGuard: AudioGuard(), sourceInstallationID: installationID, beforeVerification: { _ in
            throw POSIXError(.ENOSPC)
        })
        await #expect(throws: SnapshotError.ioFailure) { try await failing.createPortableArchive(at: fixture.destination, recoveryKey: key) }
        #expect(!FileManager.default.fileExists(atPath: fixture.destination.path))
        #expect(try fixture.leftovers().isEmpty)
        let cancelled = SnapshotService(store: store, audioGuard: AudioGuard(), sourceInstallationID: installationID, beforeVerification: { _ in
            withUnsafeCurrentTask { $0?.cancel() }
        })
        let task = Task { try await cancelled.createPortableArchive(at: fixture.destination, recoveryKey: key) }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: fixture.destination.path))
        #expect(try fixture.leftovers().isEmpty)
    }

    @Test func wrongKeyTamperingAndFrameOrderAreRejected() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = try await fixture.store(large: true)
        let key = try RecoveryKey.generate()
        _ = try await SnapshotService(store: store, audioGuard: AudioGuard(), sourceInstallationID: installationID).createPortableArchive(at: fixture.destination, recoveryKey: key)
        #expect(throws: SnapshotError.authenticationFailed) { try PortableArchive.verify(at: fixture.destination, recoveryKey: .generate()) }
        let original = try Data(contentsOf: fixture.destination)
        let parts = try split(original)
        let prefix = parts.header + parts.manifest
        var header = original; header[12] ^= 1
        var salt = original; salt[28] ^= 1
        var tag = original; tag[tag.count - 1] ^= 1
        var manifest = original; manifest[70] ^= 1
        var frames = parts.frames; frames.swapAt(0, 1)
        let duplicated = prefix + parts.frames[0] + parts.frames[0] + parts.frames.dropFirst(2).reduce(Data(), +)
        let reordered = prefix + frames.reduce(Data(), +)
        let missing = prefix + parts.frames.dropLast().reduce(Data(), +)
        let mutations: [Data] = [header, salt, tag, manifest, reordered, duplicated, missing, Data(original.dropLast()), original + Data([0])]
        for mutation in mutations {
            let bad = fixture.directory.appendingPathComponent("tampered.taisa-backup")
            try mutation.write(to: bad)
            #expect(throws: SnapshotError.self) { try PortableArchive.verify(at: bad, recoveryKey: key) }
        }
        #expect(try await store.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM profile") } == 1)
    }

    @Test func capacityFailureCancellationAndIOFailureCleanUp() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = try await fixture.store()
        let key = try RecoveryKey.generate()
        let small = SnapshotService(store: store, audioGuard: AudioGuard(), sourceInstallationID: installationID, capacityPolicy: .init(maximumDatabaseBytes: 1))
        await #expect(throws: SnapshotError.insufficientCapacity) { try await small.createPortableArchive(at: fixture.destination, recoveryKey: key) }
        #expect(!FileManager.default.fileExists(atPath: fixture.destination.path))
        #expect(try fixture.leftovers().isEmpty)
        let service = SnapshotService(store: store, audioGuard: AudioGuard(), sourceInstallationID: installationID)
        let task = Task { try await Task.sleep(for: .seconds(1)); return try await service.createPortableArchive(at: fixture.destination, recoveryKey: key) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        let bad = fixture.directory.appendingPathComponent("missing/backup.taisa-backup")
        await #expect(throws: SnapshotError.ioFailure) { try await service.createPortableArchive(at: bad, recoveryKey: key) }
        #expect(try fixture.leftovers().isEmpty)
    }

    @Test func authenticatedWrongDigestAndReusedNoncesAreRejected() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = try await fixture.store(large: true)
        let key = try RecoveryKey.generate()
        _ = try await SnapshotService(store: store, audioGuard: AudioGuard(), sourceInstallationID: installationID, clock: { instant }).createPortableArchive(at: fixture.destination, recoveryKey: key)
        let original = try Data(contentsOf: fixture.destination)
        for reuseNonce in [false, true] {
            let rebuilt = try rebuild(original, recoveryKey: key, wrongDigest: !reuseNonce, reuseNonce: reuseNonce)
            let bad = fixture.directory.appendingPathComponent("invalid.taisa-backup")
            try rebuilt.write(to: bad)
            #expect(throws: SnapshotError.self) { try PortableArchive.verify(at: bad, recoveryKey: key) }
        }
    }

    @Test func authenticatedChunkCountOutsideWireRangeFailsWithoutTrapping() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = try await fixture.store(large: true)
        let key = try RecoveryKey.generate()
        _ = try await SnapshotService(store: store, audioGuard: AudioGuard(), sourceInstallationID: installationID, clock: { instant }).createPortableArchive(at: fixture.destination, recoveryKey: key)
        let original = try Data(contentsOf: fixture.destination)
        let bytes = try rebuild(original, recoveryKey: key, wrongDigest: false, reuseNonce: false, oversizedCount: true)
        let bad = fixture.directory.appendingPathComponent("oversized.taisa-backup")
        try bytes.write(to: bad)
        #expect(throws: SnapshotError.self) { try PortableArchive.verify(at: bad, recoveryKey: key, maximumPayloadBytes: Int64.max) }
    }

    @Test func malformedHeaderLengthsVersionsAndCrossArchiveFramesFailClosed() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = try await fixture.store(large: true)
        let key = try RecoveryKey.generate()
        let service = SnapshotService(store: store, audioGuard: AudioGuard(), sourceInstallationID: installationID)
        _ = try await service.createPortableArchive(at: fixture.destination, recoveryKey: key)
        let secondURL = fixture.directory.appendingPathComponent("second.taisa-backup")
        _ = try await service.createPortableArchive(at: secondURL, recoveryKey: key)
        let original = try Data(contentsOf: fixture.destination)
        let first = try split(original)
        let second = try split(Data(contentsOf: secondURL))
        #expect(first.header.subdata(in: 28..<60) != second.header.subdata(in: 28..<60))
        var magic = original; magic[0] ^= 1
        var version = original; version[11] = 2
        var length = original; length.replaceSubrange(60..<64, with: Data(repeating: 255, count: 4))
        var frameLength = original
        frameLength.replaceSubrange(64 + first.manifest.count..<68 + first.manifest.count, with: Data(repeating: 255, count: 4))
        let splice = first.header + first.manifest + second.frames.reduce(Data(), +)
        let malformed: [Data] = [magic, version, length, frameLength, Data(original.prefix(7)), splice]
        for bytes in malformed {
            let bad = fixture.directory.appendingPathComponent("bad.taisa-backup")
            try bytes.write(to: bad)
            #expect(throws: SnapshotError.self) { try PortableArchive.verify(at: bad, recoveryKey: key) }
        }
        #expect(throws: SnapshotError.self) { try PortableArchive.verify(at: fixture.destination, recoveryKey: key, maximumPayloadBytes: 1) }
    }

    @Test func corruptStagedArchiveNeverPublishesAndExistingDestinationSurvives() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = try await fixture.store()
        let key = try RecoveryKey.generate()
        let service = SnapshotService(store: store, audioGuard: AudioGuard(), sourceInstallationID: installationID, beforeVerification: { url in
            let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
            try handle.seek(toOffset: 70); try handle.write(contentsOf: Data(repeating: 0, count: 16))
        })
        await #expect(throws: SnapshotError.self) { try await service.createPortableArchive(at: fixture.destination, recoveryKey: key) }
        #expect(!FileManager.default.fileExists(atPath: fixture.destination.path))
        #expect(try fixture.leftovers().isEmpty)
        try Data("existing".utf8).write(to: fixture.destination)
        let ordinary = SnapshotService(store: store, audioGuard: AudioGuard(), sourceInstallationID: installationID)
        await #expect(throws: SnapshotError.destinationExists) { try await ordinary.createPortableArchive(at: fixture.destination, recoveryKey: key) }
        #expect(try Data(contentsOf: fixture.destination) == Data("existing".utf8))
    }

    private func split(_ data: Data) throws -> (header: Data, manifest: Data, frames: [Data]) {
        let length = Int(data[60..<64].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
        var offset = 64 + length
        var frames = [Data]()
        while offset < data.count {
            let count = Int(data[offset..<offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
            frames.append(data.subdata(in: offset..<offset + 4 + count)); offset += 4 + count
        }
        return (data.prefix(64), data.subdata(in: 64..<64 + length), frames)
    }

    /// Independent, authenticated malicious fixtures: valid AEAD is insufficient
    /// when the manifest hash is false or nonces are reused.
    private func rebuild(_ archive: Data, recoveryKey: RecoveryKey, wrongDigest: Bool, reuseNonce: Bool, oversizedCount: Bool = false) throws -> Data {
        let parts = try split(archive)
        let material = Data(recoveryKey.formatted.split(separator: "-")[1...8].joined().hexBytes)
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: material), salt: parts.header.subdata(in: 28..<60), info: Data("taisa.portable-backup.frames.v1".utf8), outputByteCount: 32)
        let originalManifest = try AES.GCM.open(AES.GCM.SealedBox(combined: parts.manifest), using: key, authenticating: parts.header)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let decoded = try decoder.decode(SnapshotManifest.self, from: originalManifest)
        let modified = SnapshotManifest(formatVersion: decoded.formatVersion, schemaVersion: decoded.schemaVersion,
            createdAt: decoded.createdAt, sourceInstallationID: decoded.sourceInstallationID,
            plaintextByteCount: oversizedCount ? (Int64(UInt32.max) + 1) * 1_048_576 : decoded.plaintextByteCount,
            plaintextSHA256: wrongDigest ? Data(repeating: 0, count: 32) : decoded.plaintextSHA256,
            entityCounts: decoded.entityCounts, chunkCount: oversizedCount ? Int(UInt32.max) + 1 : decoded.chunkCount)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let manifest = try encoder.encode(modified)
        var header = parts.header; header.replaceSubrange(60..<64, with: u32(manifest.count + 28))
        let reused = AES.GCM.Nonce()
        var result = header + (try AES.GCM.seal(manifest, using: key, nonce: reused, authenticating: header).combined!)
        for (index, frame) in parts.frames.enumerated() {
            let oldAAD = parts.header + Data(SHA256.hash(data: originalManifest)) + u32(index) + u32(parts.frames.count)
            let payload = try AES.GCM.open(AES.GCM.SealedBox(combined: Data(frame.dropFirst(4))), using: key, authenticating: oldAAD)
            let aad = header + Data(SHA256.hash(data: manifest)) + u32(index) + u32(parts.frames.count)
            let sealed = try AES.GCM.seal(payload, using: key, nonce: reuseNonce ? reused : AES.GCM.Nonce(), authenticating: aad).combined!
            result += u32(sealed.count) + sealed
        }
        return result
    }

    private func u32(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(value).bigEndian) { Data($0) } }
}

private extension String {
    var hexBytes: [UInt8] {
        let chars = Array(self)
        return stride(from: 0, to: chars.count, by: 2).map { UInt8(String(chars[$0...$0 + 1]), radix: 16)! }
    }
}

private actor CheckpointPause {
    private var held = false
    private var heldWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    func hold() async {
        held = true
        for waiter in heldWaiters { waiter.resume() }
        heldWaiters.removeAll()
        await withCheckedContinuation { releaseWaiter = $0 }
    }
    func waitUntilHeld() async {
        if held { return }
        await withCheckedContinuation { heldWaiters.append($0) }
    }
    func release() { releaseWaiter?.resume() }
}
