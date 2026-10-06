import Foundation
import TaisaStorage

public enum SyncMergeError: Error, Sendable, Equatable, CustomStringConvertible {
    case unsupportedVersion
    case malformedMutation
    case identityMismatch
    case duplicateDeviceCounter
    case persistenceFailed
    case alreadyResolved

    public var description: String {
        switch self {
        case .unsupportedVersion: "Unsupported sync version"
        case .malformedMutation: "Malformed sync mutation"
        case .identityMismatch: "Sync identity mismatch"
        case .duplicateDeviceCounter: "Duplicate device counter"
        case .persistenceFailed: "Sync persistence failed"
        case .alreadyResolved: "Sync conflict already resolved"
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
    public let resolvedParentVersionIDs: [String]?
    public let retainedDeletionEvidence: SyncDeletionSummary?

    public init(id: String, entityType: String, entityID: String, entityVersion: Int, deviceID: String, counter: Int64, timestampMS: Int64, kind: Kind, fields: [SyncField], observedFieldVersions: [SyncObservedField] = [], frontier: VersionVector? = nil, recordParentVersionID: String? = nil, resolvedParentVersionIDs: [String]? = nil, retainedDeletionEvidence: SyncDeletionSummary? = nil) {
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
        self.resolvedParentVersionIDs = resolvedParentVersionIDs
        self.retainedDeletionEvidence = retainedDeletionEvidence
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
            recordParentVersionID: causality.recordParentVersionID,
            resolvedParentVersionIDs: causality.resolvedParentVersionIDs,
            retainedDeletionEvidence: causality.retainedDeletionCausality.map { retained in
                SyncDeletionSummary(id: retained.versionIDs.first ?? "", eventIDs: retained.versionIDs, timestampMS: retained.latestDeletedAtMS, frontier: VersionVector(entries: retained.frontier.map { DeviceCounter(deviceID: $0.deviceID, counter: $0.counter) }), observedFieldVersions: retained.observedFieldVersions.map { SyncObservedField(name: $0.fieldName, versionID: $0.versionID) }, fieldAncestry: retained.fieldAncestry)
            }
        )
        try validate()
    }

    /// The serialized shape is the existing Task 3 CausalSnapshot contract.
    public func journalCausality() throws -> CausalSnapshot {
        try validate()
        let versions = fields.map { field in
            JournalField(fieldName: field.name, versionID: field.versionID, parentVersionID: field.ancestorVersionIDs.first, ancestorVersionIDs: field.ancestorVersionIDs, deviceCounter: field.deviceCounter)
        }
        let retained = retainedDeletionEvidence.map { evidence in
            JournalRetainedDeletion(versionIDs: evidence.eventIDs, latestDeletedAtMS: evidence.timestampMS, frontier: evidence.frontier.entries.map { JournalDeviceCounter(deviceID: $0.deviceID, counter: $0.counter) }, observedFieldVersions: evidence.observedFieldVersions.map { JournalObserved(fieldName: $0.name, versionID: $0.versionID) }, fieldAncestry: evidence.fieldAncestry)
        }
        let projection = JournalSnapshot(logicalVersionID: id, recordParentVersionID: recordParentVersionID, resolvedParentVersionIDs: resolvedParentVersionIDs, retainedDeletionCausality: retained, deviceID: deviceID, deviceCounter: counter, changedFields: versions, observedFieldVersions: observedFieldVersions.map { JournalObserved(fieldName: $0.name, versionID: $0.versionID) })
        return try JSONDecoder().decode(CausalSnapshot.self, from: JSONEncoder().encode(projection))
    }

    func validate() throws {
        guard entityVersion == 1 else { throw SyncMergeError.unsupportedVersion }
        guard Self.entities.contains(entityType), UUID(uuidString: id) != nil, UUID(uuidString: entityID) != nil,
              UUID(uuidString: deviceID) != nil, counter > 0, timestampMS >= 0,
              frontier.isValid, frontier.counter(for: deviceID) == counter,
              recordParentVersionID.map({ UUID(uuidString: $0) != nil }) ?? true,
              (resolvedParentVersionIDs ?? []).allSatisfy({ UUID(uuidString: $0) != nil }),
              Set((resolvedParentVersionIDs ?? []).compactMap { UUID(uuidString: $0) }).count == (resolvedParentVersionIDs ?? []).count,
              !(resolvedParentVersionIDs ?? []).contains(where: { UUID(uuidString: $0) == UUID(uuidString: id) }),
              Set(fields.map(\.name)).count == fields.count,
              Set(observedFieldVersions.map(\.name)).count == observedFieldVersions.count,
              (kind != .delete || fields.isEmpty),
              (kind == .delete || !fields.isEmpty || (kind == .update && recordParentVersionID != nil)) else { throw SyncMergeError.malformedMutation }
        if entityType == "message" && kind != .create && kind != .delete { throw SyncMergeError.malformedMutation }
        if let retainedDeletionEvidence {
            guard kind == .delete else { throw SyncMergeError.malformedMutation }
            let evidence = try retainedDeletionEvidence.validated()
            let parents = Set((resolvedParentVersionIDs ?? []).compactMap { UUID(uuidString: $0)?.uuidString })
            guard Set(evidence.eventIDs).isSubset(of: parents),
                  !(evidence.fieldAncestry ?? [:]).values.flatMap({ $0 }).contains(UUID(uuidString: id)?.uuidString ?? id),
                  evidence.frontier.counter(for: deviceID).map({ $0 < counter }) ?? true else { throw SyncMergeError.malformedMutation }
        }
        if !fields.isEmpty && !(resolvedParentVersionIDs ?? []).isEmpty && kind != .resolve { throw SyncMergeError.malformedMutation }
        if kind == .resolve && !(resolvedParentVersionIDs ?? []).isEmpty {
            let resolved = Set((resolvedParentVersionIDs ?? []).compactMap { UUID(uuidString: $0) })
            guard fields.allSatisfy({ resolved.isSubset(of: Set($0.ancestorVersionIDs.compactMap { UUID(uuidString: $0) })) }),
                  recordParentVersionID.map({ resolved.contains(UUID(uuidString: $0)!) }) ?? true else { throw SyncMergeError.malformedMutation }
        }
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

    func canonicalized() -> SyncMutation {
        func key(_ value: String) -> String { UUID(uuidString: value)!.uuidString }
        let retained = retainedDeletionEvidence.map { evidence in
            SyncDeletionSummary(id: key(evidence.id), eventIDs: evidence.eventIDs.map(key).sorted(), timestampMS: evidence.timestampMS, frontier: evidence.frontier.canonicalized(), observedFieldVersions: evidence.observedFieldVersions.map { SyncObservedField(name: $0.name, versionID: key($0.versionID)) }.sorted { ($0.name, $0.versionID) < ($1.name, $1.versionID) }, fieldAncestry: evidence.fieldAncestry.flatMap { $0.isEmpty ? nil : $0.mapValues { $0.map(key).sorted() } })
        }
        return SyncMutation(id: key(id), entityType: entityType, entityID: key(entityID), entityVersion: entityVersion, deviceID: key(deviceID), counter: counter, timestampMS: timestampMS, kind: kind,
            fields: fields.map { SyncField(name: $0.name, value: $0.value, versionID: key($0.versionID), ancestorVersionIDs: $0.ancestorVersionIDs.map(key), deviceCounter: $0.deviceCounter) }.sorted { $0.name < $1.name },
            observedFieldVersions: observedFieldVersions.map { SyncObservedField(name: $0.name, versionID: key($0.versionID)) }.sorted { $0.name < $1.name },
            frontier: frontier.canonicalized(), recordParentVersionID: recordParentVersionID.map(key), resolvedParentVersionIDs: resolvedParentVersionIDs?.map(key).sorted(), retainedDeletionEvidence: retained)
    }
}

private struct JournalSnapshot: Encodable {
    let logicalVersionID: String
    let recordParentVersionID: String?
    let resolvedParentVersionIDs: [String]?
    let retainedDeletionCausality: JournalRetainedDeletion?
    let deviceID: String
    let deviceCounter: Int64
    let changedFields: [JournalField]
    let observedFieldVersions: [JournalObserved]
}
private struct JournalRetainedDeletion: Encodable {
    let versionIDs: [String]
    let latestDeletedAtMS: Int64
    let frontier: [JournalDeviceCounter]
    let observedFieldVersions: [JournalObserved]
    let fieldAncestry: [String: [String]]?
}
private struct JournalDeviceCounter: Encodable {
    let deviceID: String
    let counter: Int64
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
