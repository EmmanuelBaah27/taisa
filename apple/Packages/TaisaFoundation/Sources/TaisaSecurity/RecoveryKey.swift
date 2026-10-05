import CryptoKit
import Foundation
import Security

public enum VaultError: Error, Equatable, Sendable, CustomStringConvertible {
    case randomGenerationFailed
    case invalidRecoveryKey
    case invalidKeyLength
    case malformedEnvelope
    case unsupportedVersion
    case authenticationFailed
    case wrongRecoveryKey

    public var description: String {
        switch self {
        case .randomGenerationFailed: "random_generation_failed"
        case .invalidRecoveryKey: "invalid_recovery_key"
        case .invalidKeyLength: "invalid_key_length"
        case .malformedEnvelope: "malformed_envelope"
        case .unsupportedVersion: "unsupported_version"
        case .authenticationFailed: "authentication_failed"
        case .wrongRecoveryKey: "wrong_recovery_key"
        }
    }
}

enum SecurityRandom {
    static func bytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        defer { for index in bytes.indices { bytes[index] = 0 } }
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw VaultError.randomGenerationFailed
        }
        return Data(bytes)
    }
}

/// A 256-bit generated secret. Only `formatted` is suitable for a short authenticated ceremony.
/// Swift Data/CryptoKit may retain value copies; zeroing the temporary RNG buffer cannot clear those copies.
public struct RecoveryKey: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private static let prefix = "TAISA1"
    private static let checksumContext = Data("taisa.recovery.v1".utf8)
    let keyMaterial: Data

    public static func generate() throws -> RecoveryKey {
        try RecoveryKey(keyMaterial: SecurityRandom.bytes(count: 32))
    }

    init(keyMaterial: Data) throws {
        guard keyMaterial.count == 32 else { throw VaultError.invalidKeyLength }
        self.keyMaterial = keyMaterial
    }

    public init(validating text: String) throws {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let groups = normalized.split(separator: "-", omittingEmptySubsequences: false)
        guard groups.count == 10,
              groups[0] == Self.prefix,
              groups[1...8].allSatisfy({ $0.count == 8 && $0.allSatisfy(\.isASCIIHexDigit) }),
              groups[9].count == 8, groups[9].allSatisfy(\.isASCIIHexDigit),
              let material = Data(hex: groups[1...8].joined()),
              material.count == 32,
              Self.checksum(for: material) == groups[9]
        else { throw VaultError.invalidRecoveryKey }
        keyMaterial = material
    }

    public var formatted: String {
        let hex = keyMaterial.map { String(format: "%02X", $0) }.joined()
        let groups = stride(from: 0, to: hex.count, by: 8).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            return String(hex[start..<hex.index(start, offsetBy: 8)])
        }
        return ([Self.prefix] + groups + [Self.checksum(for: keyMaterial)]).joined(separator: "-")
    }

    func matches(_ other: RecoveryKey) -> Bool {
        var difference: UInt8 = 0
        for index in 0..<32 { difference |= keyMaterial[index] ^ other.keyMaterial[index] }
        return difference == 0
    }

    private static func checksum(for material: Data) -> String {
        SHA256.hash(data: checksumContext + material).prefix(4)
            .map { String(format: "%02X", $0) }.joined()
    }

    public var description: String { "<redacted recovery key>" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["state": "redacted"], displayStyle: .struct)
    }
}

private extension Character {
    var isASCIIHexDigit: Bool { unicodeScalars.count == 1 && unicodeScalars.first.map {
        (48...57).contains($0.value) || (65...70).contains($0.value)
    } == true }
}

private extension Data {
    init?(hex: String) {
        var bytes = [UInt8]()
        defer { for index in bytes.indices { bytes[index] = 0 } }
        bytes.reserveCapacity(hex.count / 2)
        let characters = Array(hex)
        guard characters.count.isMultiple(of: 2) else { return nil }
        for index in stride(from: 0, to: characters.count, by: 2) {
            guard let value = UInt8(String(characters[index...index + 1]), radix: 16) else { return nil }
            bytes.append(value)
        }
        self.init(bytes)
    }
}
