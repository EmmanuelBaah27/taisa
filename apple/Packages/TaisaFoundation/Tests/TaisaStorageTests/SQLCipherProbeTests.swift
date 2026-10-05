import Foundation
import GRDB
import Testing
@testable import TaisaStorage

@Test func encryptedDatabaseRejectsWrongKeyAndHidesPlaintext() throws {
    let result = try SQLCipherProbe.makeAndVerify(canary: "PRIVATE-CANARY")
    #expect(!result.cipherVersion.isEmpty)
    #expect(result.reopenedWithCorrectKey)
    #expect(result.wrongKeyRejected)
    #expect(result.foreignKeysEnabled)
    #expect(result.journalMode == "wal")
    #expect(!result.fileBytes.contains(Data("PRIVATE-CANARY".utf8)))
}

@Test func invalidKeyLengthFailsClosed() throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    #expect(throws: SQLCipherProbeError.invalidKeyLength) {
        try SQLCipherProbe.verify(databaseURL: databaseURL, key: Data(repeating: 0, count: 31))
    }
    #expect(!FileManager.default.fileExists(atPath: databaseURL.path))
}

@Test func missingDatabaseIsNotCreatedByVerification() throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    #expect(throws: SQLCipherProbeError.databaseMissing) {
        try SQLCipherProbe.verify(databaseURL: databaseURL, key: Data(repeating: 0, count: 32))
    }
    #expect(!FileManager.default.fileExists(atPath: databaseURL.path))
}

private struct ProbeFixtureResult {
    let cipherVersion: String
    let reopenedWithCorrectKey: Bool
    let wrongKeyRejected: Bool
    let foreignKeysEnabled: Bool
    let journalMode: String
    let fileBytes: Data
}

private extension SQLCipherProbe {
    static func makeAndVerify(canary: String) throws -> ProbeFixtureResult {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("encrypted.sqlite")
        let key = Data(repeating: 0xA5, count: 32)

        do {
            var configuration = Configuration()
            configuration.prepareDatabase { database in
                try database.usePassphrase(key)
            }
            let queue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
            try queue.write { database in
                try database.execute(sql: "CREATE TABLE secret (value TEXT NOT NULL)")
                try database.execute(sql: "INSERT INTO secret (value) VALUES (?)", arguments: [canary])
            }
        }

        let runtime = try verify(databaseURL: databaseURL, key: key)
        var reopenConfiguration = Configuration()
        reopenConfiguration.prepareDatabase { database in
            try database.usePassphrase(key)
        }
        let reopened = try DatabaseQueue(path: databaseURL.path, configuration: reopenConfiguration)
        let reopenedCanary = try reopened.read { database in
            try String.fetchOne(database, sql: "SELECT value FROM secret")
        }
        let wrongKeyRejected: Bool
        do {
            _ = try verify(databaseURL: databaseURL, key: Data(repeating: 0x5A, count: 32))
            wrongKeyRejected = false
        } catch SQLCipherProbeError.authenticationFailed {
            wrongKeyRejected = true
        }
        return ProbeFixtureResult(
            cipherVersion: runtime.cipherVersion,
            reopenedWithCorrectKey: reopenedCanary == canary,
            wrongKeyRejected: wrongKeyRejected,
            foreignKeysEnabled: runtime.foreignKeysEnabled,
            journalMode: runtime.journalMode,
            fileBytes: try Data(contentsOf: databaseURL)
        )
    }
}
