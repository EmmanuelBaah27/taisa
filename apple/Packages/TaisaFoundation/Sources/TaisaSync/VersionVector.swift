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

    public func merged(with other: VersionVector) -> VersionVector? {
        guard isValid, other.isValid else { return nil }
        var values: [String: Int64] = [:]
        for entry in entries + other.entries {
            let key = UUID(uuidString: entry.deviceID)!.uuidString
            values[key] = max(values[key] ?? 0, entry.counter)
        }
        return VersionVector(entries: values.keys.sorted().map { DeviceCounter(deviceID: $0, counter: values[$0]!) })
    }

    func canonicalized() -> VersionVector {
        VersionVector(entries: entries.map { DeviceCounter(deviceID: UUID(uuidString: $0.deviceID)!.uuidString, counter: $0.counter) }.sorted { $0.deviceID < $1.deviceID })
    }

    /// Strict acknowledgement: equality still permits replay of the deletion.
    public func isBeyond(_ other: VersionVector) -> Bool {
        guard isValid, other.isValid, !other.entries.isEmpty else { return false }
        var advanced = false
        for entry in other.entries {
            guard let acknowledged = counter(for: entry.deviceID), acknowledged >= entry.counter else { return false }
            advanced = advanced || acknowledged > entry.counter
        }
        for entry in entries where other.counter(for: entry.deviceID) == nil {
            advanced = advanced || entry.counter > 0
        }
        return advanced
    }
}
