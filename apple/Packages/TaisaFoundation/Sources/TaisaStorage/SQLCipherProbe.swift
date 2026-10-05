import Foundation
import GRDB

public struct SQLCipherRuntime: Sendable {
    public let cipherVersion: String
    public let journalMode: String
    public let foreignKeysEnabled: Bool
}

public enum SQLCipherProbeError: Error, Equatable {
    case invalidKeyLength
    case databaseMissing
    case openFailed
    case authenticationFailed
    case cipherUnavailable
    case integrityFailed
    case configurationFailed
}

public enum SQLCipherProbe {
    /// Checks an existing encrypted store without creating one on a missing path.
    public static func verify(databaseURL: URL, key: Data) throws -> SQLCipherRuntime {
        guard key.count == 32 else { throw SQLCipherProbeError.invalidKeyLength }
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw SQLCipherProbeError.databaseMissing
        }

        var configuration = Configuration()
        configuration.prepareDatabase { database in
            // SQLCipher must receive the bytes before any page or schema is read.
            try database.usePassphrase(key)
        }

        let queue: DatabaseQueue
        do {
            queue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        } catch let error as DatabaseError where error.resultCode == .SQLITE_NOTADB {
            // GRDB validates sqlite_master during initialization, so a wrong
            // key fails before DatabaseQueue is returned.
            throw SQLCipherProbeError.authenticationFailed
        } catch {
            throw SQLCipherProbeError.openFailed
        }

        do {
            return try queue.inDatabase { database in
                guard let version = try String.fetchOne(database, sql: "PRAGMA cipher_version"),
                      !version.isEmpty else {
                    throw SQLCipherProbeError.cipherUnavailable
                }

                // Ensure an encrypted page can be read before accepting the key.
                _ = try Int.fetchOne(database, sql: "PRAGMA user_version")

                try database.execute(sql: "PRAGMA foreign_keys = ON")
                let foreignKeysEnabled = try Int.fetchOne(database, sql: "PRAGMA foreign_keys") == 1
                let journalMode = try String.fetchOne(database, sql: "PRAGMA journal_mode = WAL") ?? ""
                guard foreignKeysEnabled, journalMode.lowercased() == "wal" else {
                    throw SQLCipherProbeError.configurationFailed
                }

                let integrityErrors = try String.fetchAll(database, sql: "PRAGMA cipher_integrity_check")
                guard integrityErrors.isEmpty else {
                    throw SQLCipherProbeError.integrityFailed
                }
                return SQLCipherRuntime(
                    cipherVersion: version,
                    journalMode: journalMode.lowercased(),
                    foreignKeysEnabled: foreignKeysEnabled
                )
            }
        } catch let error as SQLCipherProbeError {
            throw error
        } catch let error as DatabaseError where error.resultCode == .SQLITE_NOTADB {
            throw SQLCipherProbeError.authenticationFailed
        } catch {
            throw SQLCipherProbeError.openFailed
        }
    }
}
