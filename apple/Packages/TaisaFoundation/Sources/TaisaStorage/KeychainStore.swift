import Foundation
import Security

/// The production key store. Its service is scoped to the app's Keychain access group.
public actor KeychainStore: DatabaseKeyStore {
    public static let service = "taisa.database-key.v1"

    public init() {}

    public func loadKey() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: "database",
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let key = result as? Data else {
            throw StorageError.keychainFailure(status)
        }
        return key
    }

    public func saveKey(_ key: Data) throws {
        guard key.count == 32 else { throw StorageError.invalidKeyLength }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: "database",
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: key,
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw StorageError.keychainFailure(status) }
    }
}
