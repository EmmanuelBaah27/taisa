import Foundation
import TaisaStorage

public enum SyncMergeError: Error, Sendable, Equatable, CustomStringConvertible {
    case unsupportedVersion
    case malformedMutation
    case identityMismatch
    case duplicateDeviceCounter
    case persistenceFailed

    public var description: String {
        switch self {
        case .unsupportedVersion: "Unsupported sync version"
        case .malformedMutation: "Malformed sync mutation"
        case .identityMismatch: "Sync identity mismatch"
        case .duplicateDeviceCounter: "Duplicate device counter"
        case .persistenceFailed: "Sync persistence failed"
        }
    }
}

public struct SyncField: Codable, Sendable, Equatable {
    public let name: String
    public let value: Data
    public let versionID: String
    /// Causal ancestors, nearest first. A resolution names both competing parents.
    public let ancestorVersionIDs: [String]
    public let deviceCounter: Int64

    public init(name: String, value: Data, versionID: String, ancestorVersionIDs: [String] = [], deviceCounter: Int64) {
        self.name = name
        self.value = value
        self.versionID = versionID
        self.ancestorVersionIDs = ancestorVersionIDs
        self.deviceCounter = deviceCounter
    }
}

public struct SyncObservedField: Codable, Sendable, Equatable {
    public let name: String
    public let versionID: String

    public init(name: String, versionID: String) {
        self.name = name
        self.versionID = versionID
    }
}

public struct SyncMutation: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case create, update, delete, resolve }

    public let id: String
    public let entityType: String
    public let entityID: String
    public let entityVersion: Int
    public let deviceID: String
    public let counter: Int64
    /// Display metadata only. Merge never compares this value.
    public let timestampMS: Int64
    public let kind: Kind
    public let fields: [SyncField]
    public let observedFieldVersions: [SyncObservedField]
    public let frontier: VersionVector
    public let recordParentVersionID: String?

    public init(id: String, entityType: String, entityID: String, entityVersion: Int, deviceID: String, counter: Int64, timestampMS: Int64, kind: Kind, fields: [SyncField], observedFieldVersions: [SyncObservedField] = [], frontier: VersionVector? = nil, recordParentVersionID: String? = nil) {
        self.id = id
        self.entityType = entityType
        self.entityID = entityID
        self.entityVersion = entityVersion
        self.deviceID = deviceID
        self.counter = counter
        self.timestampMS = timestampMS
        self.kind = kind
        self.fields = fields
        self.observedFieldVersions = observedFieldVersions
        self.frontier = frontier ?? VersionVector(entries: [DeviceCounter(deviceID: deviceID, counter: counter)])
        self.recordParentVersionID = recordParentVersionID
    }

    /// Adapts Task 3's committed causal snapshot without adding GRDB to this API.
    public init(id: String, entityType: String, entityID: String, entityVersion: Int, timestampMS: Int64, kind: Kind, fieldValues: [String: Data], causality: CausalSnapshot) throws {
        guard UUID(uuidString: causality.logicalVersionID) == UUID(uuidString: id),
              Set(causality.changedFields.map(\.fieldName)) == Set(fieldValues.keys),
              causality.changedFields.count == fieldValues.count else { throw SyncMergeError.malformedMutation }
        self.init(
            id: id, entityType: entityType, entityID: entityID, entityVersion: entityVersion,
            deviceID: causality.deviceID, counter: causality.deviceCounter, timestampMS: timestampMS,
            kind: kind,
            fields: causality.changedFields.compactMap { field in
                fieldValues[field.fieldName].map {
                    SyncField(name: field.fieldName, value: $0, versionID: field.versionID, ancestorVersionIDs: field.ancestorVersionIDs, deviceCounter: field.deviceCounter)
                }
            },
            observedFieldVersions: causality.observedFieldVersions.map { SyncObservedField(name: $0.fieldName, versionID: $0.versionID) },
            recordParentVersionID: causality.recordParentVersionID
        )
        try validate()
    }

    /// The serialized shape is the existing Task 3 CausalSnapshot contract.
    public func journalCausality() throws -> CausalSnapshot {
        try validate()
        let versions = fields.map { field in
            JournalField(fieldName: field.name, versionID: field.versionID, parentVersionID: field.ancestorVersionIDs.first, ancestorVersionIDs: field.ancestorVersionIDs, deviceCounter: field.deviceCounter)
        }
        let projection = JournalSnapshot(logicalVersionID: id, recordParentVersionID: recordParentVersionID, deviceID: deviceID, deviceCounter: counter, changedFields: versions, observedFieldVersions: observedFieldVersions.map { JournalObserved(fieldName: $0.name, versionID: $0.versionID) })
        return try JSONDecoder().decode(CausalSnapshot.self, from: JSONEncoder().encode(projection))
    }

    func validate() throws {
        guard entityVersion == 1 else { throw SyncMergeError.unsupportedVersion }
        guard Self.entities.contains(entityType), UUID(uuidString: id) != nil, UUID(uuidString: entityID) != nil,
              UUID(uuidString: deviceID) != nil, counter > 0, timestampMS >= 0,
              frontier.isValid, frontier.counter(for: deviceID) == counter,
              recordParentVersionID.map({ UUID(uuidString: $0) != nil }) ?? true,
              Set(fields.map(\.name)).count == fields.count,
              Set(observedFieldVersions.map(\.name)).count == observedFieldVersions.count,
              (kind != .delete || fields.isEmpty),
              (kind == .delete || !fields.isEmpty) else { throw SyncMergeError.malformedMutation }
        for field in fields {
            guard !field.name.isEmpty, field.name != "__record", UUID(uuidString: field.versionID) == UUID(uuidString: id),
                  field.deviceCounter == counter,
                  Set(field.ancestorVersionIDs.compactMap { UUID(uuidString: $0) }).count == field.ancestorVersionIDs.count,
                  !field.ancestorVersionIDs.contains(where: { UUID(uuidString: $0) == UUID(uuidString: id) }),
                  field.ancestorVersionIDs.allSatisfy({ UUID(uuidString: $0) != nil }) else { throw SyncMergeError.malformedMutation }
            if kind == .resolve && field.ancestorVersionIDs.count < 2 { throw SyncMergeError.malformedMutation }
        }
        for observed in observedFieldVersions {
            guard !observed.name.isEmpty, UUID(uuidString: observed.versionID) != nil else { throw SyncMergeError.malformedMutation }
        }
    }

    private static let entities: Set<String> = ["profile", "conversation", "message", "goal", "milestone", "action", "evidence", "memory", "memory_source"]
}

private struct JournalSnapshot: Encodable {
    let logicalVersionID: String
    let recordParentVersionID: String?
    let deviceID: String
    let deviceCounter: Int64
    let changedFields: [JournalField]
    let observedFieldVersions: [JournalObserved]
}
private struct JournalField: Encodable {
    let fieldName: String
    let versionID: String
    let parentVersionID: String?
    let ancestorVersionIDs: [String]
    let deviceCounter: Int64
}
private struct JournalObserved: Encodable {
    let fieldName: String
    let versionID: String
}
