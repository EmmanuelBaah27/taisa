import CryptoKit
import Foundation
import GRDB
import Testing
import TaisaSecurity
@testable import TaisaStorage
@testable import TaisaRecovery

private actor RestoreKeys: DatabaseKeyStore {
    var key = Data(repeating: 0x31, count: 32)
    var failNextSave = false
    func loadKey() -> Data? { key }
    func saveKey(_ value: Data) throws {
        if failNextSave { failNextSave = false; throw RestoreError.keyFailure }
        key = value
    }
    func failOnce() { failNextSave = true }
}
private struct RestoreAudio: AudioExportGuard { func assertNoPendingAudioReferences() async throws {} }
private struct RestoreFixture {
    let directory: URL
    let active: URL
    let archive: URL
    let recovery: RecoveryKey
    let keys = RestoreKeys()
    let store: TaisaStore
    init() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        active = directory.appendingPathComponent("active.sqlite")
        archive = directory.appendingPathComponent("backup.taisa-backup")
        recovery = try RecoveryKey.generate()
        store = try await TaisaStore.open(at: active, keyStore: keys)
        try await store.write { try $0.execute(sql: "INSERT INTO profile (id, display_name, updated_at_ms) VALUES (?, 'ARCHIVED', 1)", arguments: [UUID().uuidString]) }
        _ = try await SnapshotService(store: store, audioGuard: RestoreAudio(), sourceInstallationID: UUID()).createPortableArchive(at: archive, recoveryKey: recovery)
        try await store.write { try $0.execute(sql: "UPDATE profile SET display_name = 'ORIGINAL'") }
    }
    func coordinator(space: Int64 = Int64.max, fault: @escaping @Sendable (RestoreFaultPoint) throws -> Void = { _ in }) -> RestoreCoordinator {
        RestoreCoordinator(activeStoreURL: active, keyStore: keys, freeSpace: { _ in space }, fault: fault)
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
    func files() throws -> [String: Data] {
        var value: [String: Data] = [:]
        for suffix in ["", "-wal"] where FileManager.default.fileExists(atPath: active.path + suffix) {
            value[suffix] = try Data(contentsOf: URL(fileURLWithPath: active.path + suffix))
        }
        return value
    }
}

@Suite(.serialized) struct RestoreTests {
    @Test func validatesRekeysBeforeConfirmationAndPromotesWithActiveHandles() async throws {
        let f = try await RestoreFixture(); defer { f.remove() }
        let second = try await TaisaStore.open(at: f.active, keyStore: f.keys)
        let coordinator = f.coordinator()
        let candidate = try await coordinator.validate(archiveURL: f.archive, recoveryKey: f.recovery)
        let salt = try Data(contentsOf: f.archive).subdata(in: 28..<60)
        let archiveKey = try f.recovery.derivePortableBackupKey(salt: salt, purpose: .database).withUnsafeBytes { Data($0) }
        #expect(candidate.databaseKey.count == 32)
        #expect(candidate.databaseKey != archiveKey)
        #expect(throws: Error.self) { try TaisaStore.validateReplacement(at: candidate.databaseURL, key: archiveKey) }
        #expect(try FileManager.default.attributesOfItem(atPath: candidate.directory.path)[.posixPermissions] as? Int == 0o700)
        #expect(await f.keys.loadKey() == Data(repeating: 0x31, count: 32))
        let receipt = try await coordinator.promote(candidate, confirmReplacement: { true })
        #expect(receipt.manifest.entityCounts["profile"] == 1)
        #expect(await f.keys.loadKey() == candidate.databaseKey)
        await #expect(throws: Error.self) { try await second.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM profile") } }
        let restored = try await TaisaStore.open(at: f.active, keyStore: f.keys)
        #expect(try await restored.read { try String.fetchOne($0, sql: "SELECT display_name FROM profile") } == "ARCHIVED")
        #expect(!FileManager.default.fileExists(atPath: coordinator.journalURL.path))
    }

    @Test func declinedConfirmationAndInsufficientSpacePreserveOriginalBytesAndKey() async throws {
        let f = try await RestoreFixture(); defer { f.remove() }
        let before = try f.files()
        let size = Int64(try Data(contentsOf: f.archive).count)
        let low = f.coordinator(space: size * 2 + 100_000_000 - 1)
        await #expect(throws: RestoreError.insufficientCapacity) { try await low.validate(archiveURL: f.archive, recoveryKey: f.recovery) }
        let coordinator = f.coordinator(space: size * 2 + 100_000_000)
        let candidate = try await coordinator.validate(archiveURL: f.archive, recoveryKey: f.recovery)
        await #expect(throws: RestoreError.declined) { try await coordinator.promote(candidate, confirmReplacement: { false }) }
        #expect(try f.files() == before)
        #expect(await f.keys.loadKey() == Data(repeating: 0x31, count: 32))
    }

    @Test(arguments: ["wrong-key", "truncated", "tampered", "future-format", "future-schema", "counts", "hash"])
    func rejectsInvalidArchiveWithoutTouchingOriginal(_ mutation: String) async throws {
        let f = try await RestoreFixture(); defer { f.remove() }
        let before = try f.files()
        var bytes = try Data(contentsOf: f.archive)
        switch mutation {
        case "truncated": bytes.removeLast()
        case "tampered": bytes[bytes.count - 1] ^= 1
        case "future-format": bytes[11] = 2
        case "future-schema", "counts", "hash": bytes = try alteredManifest(bytes, recovery: f.recovery, mutation: mutation)
        default: break
        }
        try bytes.write(to: f.archive)
        await #expect(throws: Error.self) { try await f.coordinator().validate(archiveURL: f.archive, recoveryKey: mutation == "wrong-key" ? RecoveryKey.generate() : f.recovery) }
        #expect(try f.files() == before)
        #expect(await f.keys.loadKey() == Data(repeating: 0x31, count: 32))
    }

    @Test(arguments: RestoreFaultPoint.allCases)
    func relaunchRecoversEveryPhaseAndFilesystemGap(_ point: RestoreFaultPoint) async throws {
        let f = try await RestoreFixture(); defer { f.remove() }
        let before = try f.files()
        let coordinator = f.coordinator { if $0 == point { throw RestoreInterruption.simulatedCrash } }
        let candidate = try await coordinator.validate(archiveURL: f.archive, recoveryKey: f.recovery)
        await #expect(throws: RestoreInterruption.self) { try await coordinator.promote(candidate, confirmReplacement: { true }) }
        let keyWasWritten = [RestoreFaultPoint.keySaveBeforeJournal, .keyCommitted, .committed].contains(point)
        #expect(await f.keys.loadKey() == (keyWasWritten ? candidate.databaseKey : Data(repeating: 0x31, count: 32)))
        let journalBytes = try Data(contentsOf: coordinator.journalURL)
        #expect(!journalBytes.contains(candidate.databaseKey))
        #expect(!journalBytes.contains(Data(candidate.databaseKey.base64EncodedString().utf8)))
        #expect(!journalBytes.contains(Data(Data(repeating: 0x31, count: 32).base64EncodedString().utf8)))
        #expect(try FileManager.default.attributesOfItem(atPath: coordinator.journalURL.path)[.posixPermissions] as? Int == 0o600)
        let fresh = f.coordinator()
        try await fresh.recoverInterruptedPromotion()
        try await fresh.recoverInterruptedPromotion()
        if point == .committed {
            #expect(await f.keys.loadKey() == candidate.databaseKey)
        } else {
            #expect(try f.files() == before)
            #expect(await f.keys.loadKey() == Data(repeating: 0x31, count: 32))
        }
        let reopened = try await TaisaStore.open(at: f.active, keyStore: f.keys)
        #expect(try await reopened.read { try String.fetchOne($0, sql: "SELECT display_name FROM profile") } == (point == .committed ? "ARCHIVED" : "ORIGINAL"))
        #expect(!FileManager.default.fileExists(atPath: fresh.journalURL.path))
    }

    @Test func keyWriteFailureRollsBackImmediately() async throws {
        let f = try await RestoreFixture(); defer { f.remove() }
        let before = try f.files()
        let coordinator = f.coordinator()
        let candidate = try await coordinator.validate(archiveURL: f.archive, recoveryKey: f.recovery)
        await f.keys.failOnce()
        await #expect(throws: Error.self) { try await coordinator.promote(candidate, confirmReplacement: { true }) }
        #expect(try f.files() == before)
        #expect(await f.keys.loadKey() == Data(repeating: 0x31, count: 32))
    }

    @Test func normalOpenIsBlockedUntilJournalRecovery() async throws {
        let f = try await RestoreFixture(); defer { f.remove() }
        let coordinator = f.coordinator { if $0 == .originalMoved { throw RestoreInterruption.simulatedCrash } }
        let candidate = try await coordinator.validate(archiveURL: f.archive, recoveryKey: f.recovery)
        await #expect(throws: RestoreInterruption.self) { try await coordinator.promote(candidate, confirmReplacement: { true }) }
        await #expect(throws: Error.self) { try await TaisaStore.open(at: f.active, keyStore: f.keys) }
        try await f.coordinator().recoverInterruptedPromotion()
        let reopened = try await TaisaStore.open(at: f.active, keyStore: f.keys)
        #expect(try await reopened.read { try String.fetchOne($0, sql: "SELECT display_name FROM profile") } == "ORIGINAL")
    }

    @Test func corruptJournalDoesNotCloseOrCheckpointActiveStore() async throws {
        let f = try await RestoreFixture(); defer { f.remove() }
        let before = try f.files()
        let coordinator = f.coordinator()
        try Data("invalid".utf8).write(to: coordinator.journalURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: coordinator.journalURL.path)
        await #expect(throws: Error.self) { try await coordinator.recoverInterruptedPromotion() }
        #expect(try f.files() == before)
        try FileManager.default.removeItem(at: coordinator.journalURL)
        #expect(try await f.store.read { try String.fetchOne($0, sql: "SELECT display_name FROM profile") } == "ORIGINAL")
    }

    @Test func candidateMutationWhileConfirmingCannotReachKeychain() async throws {
        let f = try await RestoreFixture(); defer { f.remove() }
        let before = try f.files()
        let coordinator = f.coordinator()
        let candidate = try await coordinator.validate(archiveURL: f.archive, recoveryKey: f.recovery)
        await #expect(throws: Error.self) {
            try await coordinator.promote(candidate, confirmReplacement: {
                var bytes = try Data(contentsOf: candidate.databaseURL); bytes[0] ^= 1
                try bytes.write(to: candidate.databaseURL)
                return true
            })
        }
        #expect(try f.files() == before)
        #expect(await f.keys.loadKey() == Data(repeating: 0x31, count: 32))
    }

    @Test func candidatePathSubstitutionPreservesUnownedFile() async throws {
        let f = try await RestoreFixture(); defer { f.remove() }
        let before = try f.files()
        let coordinator = f.coordinator()
        let candidate = try await coordinator.validate(archiveURL: f.archive, recoveryKey: f.recovery)
        let sentinel = Data("UNOWNED-SENTINEL".utf8)
        await #expect(throws: Error.self) {
            try await coordinator.promote(candidate, confirmReplacement: {
                try FileManager.default.moveItem(at: candidate.databaseURL, to: candidate.directory.appendingPathComponent("retained.sqlite"))
                try sentinel.write(to: candidate.databaseURL)
                return true
            })
        }
        #expect(try Data(contentsOf: candidate.databaseURL) == sentinel)
        #expect(try f.files() == before)
    }

    @Test(arguments: RestoreFaultPoint.allCases)
    func ordinaryFailuresRollbackOrReportProvenCommit(_ point: RestoreFaultPoint) async throws {
        let f = try await RestoreFixture(); defer { f.remove() }
        let before = try f.files()
        let coordinator = f.coordinator { if $0 == point { throw RestoreError.ioFailure } }
        let candidate = try await coordinator.validate(archiveURL: f.archive, recoveryKey: f.recovery)
        if point == .committed {
            _ = try await coordinator.promote(candidate, confirmReplacement: { true })
            #expect(await f.keys.loadKey() == candidate.databaseKey)
        } else {
            await #expect(throws: Error.self) { try await coordinator.promote(candidate, confirmReplacement: { true }) }
            #expect(try f.files() == before)
            #expect(await f.keys.loadKey() == Data(repeating: 0x31, count: 32))
        }
    }

    @Test(arguments: RestoreRecoveryFaultPoint.allCases)
    func recoveryItselfCanBeInterruptedAndRetried(_ point: RestoreRecoveryFaultPoint) async throws {
        let f = try await RestoreFixture(); defer { f.remove() }
        let before = try f.files()
        let interrupted = f.coordinator { if $0 == .keyCommitted { throw RestoreInterruption.simulatedCrash } }
        let candidate = try await interrupted.validate(archiveURL: f.archive, recoveryKey: f.recovery)
        await #expect(throws: RestoreInterruption.self) { try await interrupted.promote(candidate, confirmReplacement: { true }) }
        let recovering = RestoreCoordinator(activeStoreURL: f.active, keyStore: f.keys, freeSpace: { _ in Int64.max }, fault: { _ in }, recoveryFault: {
            if $0 == point { throw RestoreInterruption.simulatedCrash }
        })
        await #expect(throws: RestoreInterruption.self) { try await recovering.recoverInterruptedPromotion() }
        try await f.coordinator().recoverInterruptedPromotion()
        #expect(try f.files() == before)
        #expect(await f.keys.loadKey() == Data(repeating: 0x31, count: 32))
        #expect(!FileManager.default.fileExists(atPath: recovering.journalURL.path))
    }

    @Test func pendingPreparedJournalBlocksRetainedWriterBeforeRecovery() async throws {
        let f = try await RestoreFixture(); defer { f.remove() }
        let before = try f.files()
        let coordinator = f.coordinator { if $0 == .prepared { throw RestoreInterruption.simulatedCrash } }
        let candidate = try await coordinator.validate(archiveURL: f.archive, recoveryKey: f.recovery)
        await #expect(throws: RestoreInterruption.self) { try await coordinator.promote(candidate, confirmReplacement: { true }) }
        await #expect(throws: Error.self) { try await f.store.write { try $0.execute(sql: "UPDATE profile SET display_name = 'LATE-WRITE'") } }
        #expect(try f.files() == before)
        try await f.coordinator().recoverInterruptedPromotion()
    }

    @Test func manifestCannotRelabelAnEmptyOlderDatabaseAsCurrentSchema() async throws {
        let f = try await RestoreFixture(); defer { f.remove() }
        let before = try f.files()
        let valid = try PortableArchive.verify(at: f.archive, recoveryKey: f.recovery)
        let salt = Data(repeating: 0x79, count: 32)
        let key = try f.recovery.derivePortableBackupKey(salt: salt, purpose: .database).withUnsafeBytes { Data($0) }
        var config = Configuration()
        let raw = Data(("x'" + key.map { String(format: "%02x", $0) }.joined() + "'").utf8)
        config.prepareDatabase { try $0.usePassphrase(raw) }
        let database = f.directory.appendingPathComponent("empty-old.sqlite")
        let queue = try DatabaseQueue(path: database.path, configuration: config)
        try await queue.write { try $0.execute(sql: "PRAGMA user_version = 0") }
        try queue.close()
        let bytes = try Data(contentsOf: database)
        var counts = valid.entityCounts; counts["profile"] = 0
        let fake = SnapshotManifest(formatVersion: 1, schemaVersion: 1, createdAt: valid.createdAt,
            sourceInstallationID: valid.sourceInstallationID, plaintextByteCount: Int64(bytes.count),
            plaintextSHA256: Data(SHA256.hash(data: bytes)), entityCounts: counts, chunkCount: 1)
        let output = try FileHandle(forWritingTo: f.archive)
        try output.truncate(atOffset: 0)
        try PortableArchive.write(database: database, manifest: fake, salt: salt, recoveryKey: f.recovery, to: output)
        try output.close()
        await #expect(throws: Error.self) { try await f.coordinator().validate(archiveURL: f.archive, recoveryKey: f.recovery) }
        #expect(try f.files() == before)
    }

    // Build authentic but semantically invalid manifests independently of the verifier.
    private func alteredManifest(_ input: Data, recovery: RecoveryKey, mutation: String) throws -> Data {
        func u32(_ n: Int) -> Data { withUnsafeBytes(of: UInt32(n).bigEndian) { Data($0) } }
        func number(_ d: Data) -> Int { d.reduce(0) { ($0 << 8) | Int($1) } }
        let header = input.prefix(64)
        let key = try recovery.derivePortableBackupKey(salt: input.subdata(in: 28..<60), purpose: .frames)
        let size = number(input.subdata(in: 60..<64))
        let original = try AES.GCM.open(AES.GCM.SealedBox(combined: input.subdata(in: 64..<64 + size)), using: key, authenticating: header)
        var object = try JSONSerialization.jsonObject(with: original) as! [String: Any]
        if mutation == "future-schema" { object["schemaVersion"] = 999 }
        if mutation == "counts" { object["entityCounts"] = ["profile": 500] }
        if mutation == "hash" { object["plaintextSHA256"] = Data(repeating: 0, count: 32).base64EncodedString() }
        let changed = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        var newHeader = Data(header); newHeader.replaceSubrange(60..<64, with: u32(changed.count + 28))
        var result = newHeader + (try AES.GCM.seal(changed, using: key, authenticating: newHeader).combined!)
        let count = object["chunkCount"] as! Int
        var offset = 64 + size
        for index in 0..<count {
            let length = number(input.subdata(in: offset..<offset + 4)); offset += 4
            let oldAAD = header + Data(SHA256.hash(data: original)) + u32(index) + u32(count)
            let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: input.subdata(in: offset..<offset + length)), using: key, authenticating: oldAAD)
            let aad = newHeader + Data(SHA256.hash(data: changed)) + u32(index) + u32(count)
            let box = try AES.GCM.seal(plain, using: key, authenticating: aad).combined!
            result += u32(box.count) + box; offset += length
        }
        return result
    }
}
