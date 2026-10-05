import Foundation

public struct DeviceCounter: Codable, Sendable, Equatable {
    public let deviceID: String
    public let counter: Int64

    public init(deviceID: String, counter: Int64) {
        self.deviceID = deviceID
        self.counter = counter
    }
}

public struct VersionVector: Codable, Sendable, Equatable {
    public let entries: [DeviceCounter]

    public init(entries: [DeviceCounter]) { self.entries = entries }

    public var isValid: Bool {
        entries.allSatisfy { UUID(uuidString: $0.deviceID) != nil && $0.counter >= 0 }
            && Set(entries.compactMap { UUID(uuidString: $0.deviceID) }).count == entries.count
    }

    public func counter(for deviceID: String) -> Int64? {
        guard let identity = UUID(uuidString: deviceID) else { return nil }
        return entries.first { UUID(uuidString: $0.deviceID) == identity }?.counter
    }

    /// Strict acknowledgement: equality still permits replay of the deletion.
    public func isBeyond(_ other: VersionVector) -> Bool {
        guard isValid, other.isValid, !other.entries.isEmpty else { return false }
        var advanced = false
        for entry in other.entries {
            guard let acknowledged = counter(for: entry.deviceID), acknowledged >= entry.counter else { return false }
            advanced = advanced || acknowledged > entry.counter
        }
        return advanced
    }
}
