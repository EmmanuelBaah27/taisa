import Foundation

/// UUID strings are case-insensitive identities. New local state and public
/// values use Foundation's uppercase, hyphenated spelling; readers accept
/// older rows persisted with another valid casing.
enum UUIDIdentity {
    static func canonical(_ value: String) -> String? {
        guard value.count == 36, let uuid = UUID(uuidString: value),
              uuid.uuidString == value.uppercased() else { return nil }
        return uuid.uuidString
    }

    static func normalizedOrOriginal(_ value: String) -> String {
        canonical(value) ?? value
    }
}
