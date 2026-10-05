import Foundation
import GRDB
import Testing
@testable import TaisaStorage

private actor MemoryDatabaseKeyStore: DatabaseKeyStore {
    private var key: Data?
    private(set) var saves = 0

    init(key: Data? = nil) { self.key = key }

    func loadKey() async throws -> Data? { key }

    func saveKey(_ key: Data) async throws {
        self.key = key
        saves += 1
    }

    func clear() { key = nil }
}

private struct StoreFixture {
    let directory: URL
    let url: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("taisa.sqlite")
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }

    func durableBytes() throws -> [String: Data] {
        var result: [String: Data] = [:]
        for suffix in ["", "-wal"] {
            let path = URL(fileURLWithPath: url.path + suffix)
            if FileManager.default.fileExists(atPath: path.path) {
                result[suffix] = try Data(contentsOf: path)
            }
        }
        return result
    }
}

@Suite(.serialized) struct TaisaStoreTests {
    @Test func freshCreationReopensWithPersistedKeyAndNoPlaintext() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let keys = MemoryDatabaseKeyStore()
        let store = try await TaisaStore.open(at: fixture.url, keyStore: keys)
        try await store.write { db in
            try db.execute(sql: "INSERT INTO profile (id, display_name, updated_at_ms) VALUES (?, ?, ?)", arguments: [UUID().uuidString, "PRIVATE-STORE-CANARY", 1_700_000_000_000])
        }
        #expect(await keys.saves == 1)
        let encryptedFiles = try fixture.durableBytes()
        #expect(encryptedFiles["-wal"] != nil)
        for bytes in encryptedFiles.values {
            #expect(!bytes.contains(Data("PRIVATE-STORE-CANARY".utf8)))
        }
        let reopened = try await TaisaStore.open(at: fixture.url, keyStore: keys)
        let value = try await reopened.read { db in try String.fetchOne(db, sql: "SELECT display_name FROM profile") }
        #expect(value == "PRIVATE-STORE-CANARY")
        #expect(await keys.saves == 1)
    }

    @Test func wrongKeyFailsWithoutReplacingIt() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let original = MemoryDatabaseKeyStore()
        _ = try await TaisaStore.open(at: fixture.url, keyStore: original)
        let before = try fixture.durableBytes()
        let wrong = MemoryDatabaseKeyStore(key: Data(repeating: 0x5a, count: 32))
        await #expect(throws: StorageError.authenticationFailed) {
            try await TaisaStore.open(at: fixture.url, keyStore: wrong)
        }
        #expect(await wrong.saves == 0)
        #expect(try fixture.durableBytes() == before)
    }

    @Test func existingDatabaseWithoutKeyFailsClosed() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let keys = MemoryDatabaseKeyStore()
        _ = try await TaisaStore.open(at: fixture.url, keyStore: keys)
        let before = try Data(contentsOf: fixture.url)
        await keys.clear()
        await #expect(throws: StorageError.missingKeyForExistingStore) {
            try await TaisaStore.open(at: fixture.url, keyStore: keys)
        }
        #expect(try Data(contentsOf: fixture.url) == before)
        #expect(await keys.saves == 1)
    }

    @Test func freshStoreHasForeignKeysWalAndCipherIntegrity() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = try await TaisaStore.open(at: fixture.url, keyStore: MemoryDatabaseKeyStore())
        let status = try await store.read { db in
            (
                try Int.fetchOne(db, sql: "PRAGMA foreign_keys"),
                try String.fetchOne(db, sql: "PRAGMA journal_mode"),
                try String.fetchOne(db, sql: "PRAGMA cipher_version"),
                try String.fetchAll(db, sql: "PRAGMA cipher_integrity_check")
            )
        }
        #expect(status.0 == 1)
        #expect(status.1?.lowercased() == "wal")
        #expect(!(status.2 ?? "").isEmpty)
        #expect(status.3.isEmpty)
        await #expect(throws: Error.self) {
            try await store.write { db in
                try db.execute(sql: "INSERT INTO messages (id, conversation_id, role, body, created_at_ms) VALUES (?, ?, ?, ?, ?)", arguments: [UUID().uuidString, UUID().uuidString, "user", "orphan", 1])
            }
        }
    }

    @Test func firstCreatedHandleWriteWaitsForSameURLPublication() async throws {
        try await assertWriteWaitsForPublication(useFirstCreatedHandle: true)
    }

    @Test func existingHandleWriteWaitsForSameURLPublication() async throws {
        try await assertWriteWaitsForPublication(useFirstCreatedHandle: false)
    }

    @Test func privateTmpAliasSharesFirstCreatedHandleOwnership() async throws {
        try await assertWriteWaitsForPublication(useFirstCreatedHandle: true, openingAlias: .tmp)
    }

    @Test func symlinkedParentAliasSharesFirstCreatedHandleOwnership() async throws {
        try await assertWriteWaitsForPublication(useFirstCreatedHandle: true, openingAlias: .symlinkedParent)
    }

    @Test func concurrentFirstOpensUseOneKeyAndCanonicalSchema() async throws {
        #if os(macOS)
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("taisa-first-opens-\(UUID().uuidString)", isDirectory: true)
        #else
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("taisa-first-opens-\(UUID().uuidString)", isDirectory: true)
        #endif
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite")
        let keys = MemoryDatabaseKeyStore()
        let stores = try await withThrowingTaskGroup(of: TaisaStore.self) { group in
            for _ in 0..<12 {
                group.addTask { try await TaisaStore.open(at: url, keyStore: keys) }
            }
            var opened: [TaisaStore] = []
            for try await store in group { opened.append(store) }
            return opened
        }
        #expect(stores.count == 12)
        #expect(await keys.saves == 1)
        for store in stores {
            #expect(try await store.read { db in try db.tableExists("messages") })
        }
    }

    @Test func distinctDatabasePathsDoNotSharePublicationOwnership() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("taisa-distinct-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appendingPathComponent("first.sqlite")
        let secondURL = directory.appendingPathComponent("second.sqlite")
        let firstKeys = MemoryDatabaseKeyStore()
        let secondKeys = MemoryDatabaseKeyStore()
        _ = try await TaisaStore.open(at: firstURL, keyStore: firstKeys)
        let second = try await TaisaStore.open(at: secondURL, keyStore: secondKeys)
        let pause = StorePublicationPause()
        let heldOpen = Task {
            try await TaisaStore.open(
                at: firstURL,
                keyStore: firstKeys,
                afterValidation: {},
                afterGeneration: { await pause.hold() }
            )
        }
        await pause.waitUntilHeld()
        let attempt = StoreWriteAttempt()
        let write = Task {
            await attempt.started()
            try await second.write { db in
                try db.execute(
                    sql: "INSERT INTO profile (id, display_name, updated_at_ms) VALUES (?, 'independent', 1)",
                    arguments: [UUID().uuidString]
                )
            }
            await attempt.finished()
        }
        await attempt.waitUntilStarted()
        try await Task.sleep(for: .milliseconds(100))
        let finishedWhileOtherOpenHeld = await attempt.isFinished
        await pause.release()
        #expect(finishedWhileOtherOpenHeld)
        _ = try await heldOpen.value
        try await write.value
    }

    private enum OpeningAlias { case sameURL, tmp, symlinkedParent }

    private func assertWriteWaitsForPublication(
        useFirstCreatedHandle: Bool,
        openingAlias: OpeningAlias = .sameURL
    ) async throws {
        #if os(macOS)
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("taisa-lifecycle-\(UUID().uuidString)", isDirectory: true)
        #else
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("taisa-lifecycle-\(UUID().uuidString)", isDirectory: true)
        #endif
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL
        let openingURL: URL
        switch openingAlias {
        case .sameURL:
            url = directory.appendingPathComponent("store.sqlite")
            openingURL = url
        case .tmp:
            url = directory.appendingPathComponent("store.sqlite")
            #if os(macOS)
            openingURL = URL(fileURLWithPath: url.path.replacingOccurrences(of: "/private/tmp/", with: "/tmp/"))
            #else
            openingURL = url
            #endif
        case .symlinkedParent:
            let real = directory.appendingPathComponent("real", isDirectory: true)
            let alias = directory.appendingPathComponent("alias", isDirectory: true)
            try FileManager.default.createDirectory(at: real, withIntermediateDirectories: false)
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
            url = real.appendingPathComponent("store.sqlite")
            openingURL = alias.appendingPathComponent("store.sqlite")
        }
        let keys = MemoryDatabaseKeyStore()
        let first = try await TaisaStore.open(at: url, keyStore: keys)
        let writerStore = useFirstCreatedHandle
            ? first
            : try await TaisaStore.open(at: url, keyStore: keys)
        let pause = StorePublicationPause()
        let heldOpen = Task {
            try await TaisaStore.open(
                at: openingURL,
                keyStore: keys,
                afterValidation: {},
                afterGeneration: { await pause.hold() }
            )
        }
        await pause.waitUntilHeld()
        let attempt = StoreWriteAttempt()
        let write = Task {
            await attempt.started()
            try await writerStore.write { db in
                try db.execute(
                    sql: "INSERT INTO profile (id, display_name, updated_at_ms) VALUES (?, 'serialized', 1)",
                    arguments: [UUID().uuidString]
                )
            }
            await attempt.finished()
        }
        await attempt.waitUntilStarted()
        try await Task.sleep(for: .milliseconds(100))
        let countWhileHeld = try await writerStore.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM profile") ?? -1
        }
        let finishedWhileHeld = await attempt.isFinished
        await pause.release()
        #expect(countWhileHeld == 0)
        #expect(!finishedWhileHeld)
        let reopened = try await heldOpen.value
        try await write.value
        #expect(try await reopened.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM profile") ?? -1
        } == 1)
    }
}

private actor StorePublicationPause {
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

private actor StoreWriteAttempt {
    private var didStart = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var isFinished = false

    func started() {
        didStart = true
        for waiter in startWaiters { waiter.resume() }
        startWaiters.removeAll()
    }

    func waitUntilStarted() async {
        if didStart { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func finished() { isFinished = true }
}
