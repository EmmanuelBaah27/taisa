import Foundation

public struct VoiceGatewayCredential: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let origin: URL
    public let credentialID: String
    public let bearerToken: String

    public init(origin: URL, credentialID: String, bearerToken: String) throws {
        self.origin = try Self.normalizedOrigin(origin)
        guard !credentialID.isEmpty, !bearerToken.isEmpty else {
            throw VoiceGatewayCredentialStoreError.invalidCredential
        }
        self.credentialID = credentialID
        self.bearerToken = bearerToken
    }

    public var description: String {
        "VoiceGatewayCredential(origin: \(origin.absoluteString), credentialID: \(credentialID), bearerToken: <redacted>)"
    }

    public var debugDescription: String { description }

    static func normalizedOrigin(_ url: URL) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil
        else {
            throw VoiceGatewayCredentialStoreError.invalidOrigin
        }

        components.scheme = "https"
        components.host = host.lowercased()
        components.path = ""
        components.query = nil
        components.fragment = nil
        guard let normalized = components.url else {
            throw VoiceGatewayCredentialStoreError.invalidOrigin
        }
        return normalized
    }
}
public enum VoiceGatewayCredentialStoreError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidOrigin
    case invalidCredential
    case invalidPersistedCredential
    case unsupportedPayloadVersion
    case keychainFailure(Int32)

    public var description: String {
        switch self {
        case .invalidOrigin: "Voice gateway credential origin is invalid."
        case .invalidCredential: "Voice gateway credential is invalid."
        case .invalidPersistedCredential: "Stored voice gateway credential is invalid."
        case .unsupportedPayloadVersion: "Stored voice gateway credential version is unsupported."
        case .keychainFailure(let status): "Voice gateway credential Keychain operation failed (\(status))."
        }
    }
}
