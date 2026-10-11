import Foundation
import Security

public protocol VoiceGatewayCredentialStoring: Sendable {
    func load(origin: URL) async throws -> VoiceGatewayCredential?
    func save(_ credential: VoiceGatewayCredential) async throws
    func delete(origin: URL) async throws
}

public actor InMemoryVoiceGatewayCredentialStore: VoiceGatewayCredentialStoring {
    private var credentials: [String: VoiceGatewayCredential] = [:]

    public init() {}

    public func load(origin: URL) throws -> VoiceGatewayCredential? {
        credentials[try Self.key(for: origin)]
    }

    public func save(_ credential: VoiceGatewayCredential) throws {
        credentials[credential.origin.absoluteString] = credential
    }

    public func delete(origin: URL) throws {
        credentials.removeValue(forKey: try Self.key(for: origin))
    }

    private static func key(for origin: URL) throws -> String {
        try VoiceGatewayCredential.normalizedOrigin(origin).absoluteString
    }
}

public actor KeychainVoiceGatewayCredentialStore: VoiceGatewayCredentialStoring {
    public static let service = "taisa.voice-gateway-credential.v1"

    public init() {}

    public func load(origin: URL) throws -> VoiceGatewayCredential? {
        let account = try Self.account(for: origin)
        var result: CFTypeRef?
        let status = SecItemCopyMatching(Self.query(account: account, returningData: true) as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw VoiceGatewayCredentialStoreError.keychainFailure(status)
        }
        let credential = try VoiceGatewayCredentialCodec.decode(data)
        guard credential.origin.absoluteString == account else {
            throw VoiceGatewayCredentialStoreError.invalidPersistedCredential
        }
        return credential
    }

    public func save(_ credential: VoiceGatewayCredential) throws {
        let account = credential.origin.absoluteString
        let data = try VoiceGatewayCredentialCodec.encode(credential)
        let query = Self.query(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw VoiceGatewayCredentialStoreError.keychainFailure(updateStatus)
        }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw VoiceGatewayCredentialStoreError.keychainFailure(addStatus)
        }
    }

    public func delete(origin: URL) throws {
        let status = SecItemDelete(Self.query(account: try Self.account(for: origin)) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VoiceGatewayCredentialStoreError.keychainFailure(status)
        }
    }

    private static func account(for origin: URL) throws -> String {
        try VoiceGatewayCredential.normalizedOrigin(origin).absoluteString
    }

    private static func query(account: String, returningData: Bool = false) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
        if returningData {
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        return query
    }
}

enum VoiceGatewayCredentialCodec {
    private struct Payload: Codable {
        let version: Int
        let origin: URL
        let credentialID: String
        let bearerToken: String
    }

    static func encode(_ credential: VoiceGatewayCredential) throws -> Data {
        do {
            return try JSONEncoder().encode(Payload(
                version: 1,
                origin: credential.origin,
                credentialID: credential.credentialID,
                bearerToken: credential.bearerToken
            ))
        } catch {
            throw VoiceGatewayCredentialStoreError.invalidCredential
        }
    }

    static func decode(_ data: Data) throws -> VoiceGatewayCredential {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw VoiceGatewayCredentialStoreError.invalidPersistedCredential
        }
        guard payload.version == 1 else {
            throw VoiceGatewayCredentialStoreError.unsupportedPayloadVersion
        }
        do {
            return try VoiceGatewayCredential(
                origin: payload.origin,
                credentialID: payload.credentialID,
                bearerToken: payload.bearerToken
            )
        } catch {
            throw VoiceGatewayCredentialStoreError.invalidPersistedCredential
        }
    }
}
