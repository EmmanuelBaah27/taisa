import Foundation

public struct SyncTombstone: Codable, Sendable, Equatable {
    public let deletionVersionID: String
    public let deletedAtMS: Int64
    public let frontier: VersionVector
    public let unresolvedConflictIDs: [String]

    public init(deletionVersionID: String, deletedAtMS: Int64, frontier: VersionVector, unresolvedConflictIDs: [String]) {
        self.deletionVersionID = deletionVersionID
        self.deletedAtMS = deletedAtMS
        self.frontier = frontier
        self.unresolvedConflictIDs = unresolvedConflictIDs
    }
}

public struct SyncDevice: Codable, Sendable, Equatable {
    public let id: String
    public let acknowledgedFrontier: VersionVector?
    public let removedAtMS: Int64?
    public let removalEventSynchronized: Bool

    public init(id: String, acknowledgedFrontier: VersionVector?, removedAtMS: Int64?, removalEventSynchronized: Bool) {
        self.id = id
        self.acknowledgedFrontier = acknowledgedFrontier
        self.removedAtMS = removedAtMS
        self.removalEventSynchronized = removalEventSynchronized
    }
}

public enum TombstonePolicy {
    public static let minimumRetentionMS: Int64 = 90 * 86_400_000

    public static func mayPurge(_ tombstone: SyncTombstone, devices: [SyncDevice], nowMS: Int64) -> Bool {
        guard UUID(uuidString: tombstone.deletionVersionID) != nil,
              tombstone.deletedAtMS >= 0, nowMS >= tombstone.deletedAtMS,
              tombstone.frontier.isValid, !tombstone.frontier.entries.isEmpty,
              tombstone.unresolvedConflictIDs.isEmpty,
              !devices.isEmpty,
              Set(devices.compactMap { UUID(uuidString: $0.id) }).count == devices.count else { return false }
        let (earliest, overflow) = tombstone.deletedAtMS.addingReportingOverflow(minimumRetentionMS)
        guard !overflow, nowMS >= earliest else { return false }
        for device in devices {
            guard UUID(uuidString: device.id) != nil,
                  (device.removedAtMS.map { $0 >= 0 } ?? true),
                  !(device.removalEventSynchronized && device.removedAtMS == nil) else { return false }
            if device.removedAtMS != nil && device.removalEventSynchronized { continue }
            guard let frontier = device.acknowledgedFrontier, frontier.isBeyond(tombstone.frontier) else { return false }
        }
        return true
    }
}
