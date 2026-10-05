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
}
