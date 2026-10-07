import Foundation
import Security

/// Device-local SQLCipher key storage. Implementations must never synchronize the key.
public protocol DatabaseKeyStore: Sendable {
    func loadKey() async throws -> Data?
    func saveKey(_ key: Data) async throws
    /// Atomically replaces an existing device-local key during a journaled restore.
    func replaceKey(_ key: Data) async throws
}

public extension DatabaseKeyStore {
    func replaceKey(_ key: Data) async throws { try await saveKey(key) }
}

enum DatabaseKeyGenerator {
    static func generate() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw StorageError.randomGenerationFailed
        }
        return Data(bytes)
    }
}
