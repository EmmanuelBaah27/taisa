import Foundation
import GRDB
import TaisaStorage

struct SyncEngineCheckpoint: Codable, Sendable {
    var received: [String: Data] = [:]
    var retryAtMS: Int64?
}

/// The journal's canonical payload is the only plaintext wire input. All of
/// these projections live inside SQLCipher or transient memory.
struct SyncProjection {
    let mutation: SyncMutation
    let payload: Data

    init(_ payload: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let id = object["id"] as? String,
              let entityType = object["entityType"] as? String,
              let entityID = object["entityID"] as? String,
              let operation = object["operation"] as? String,
              let timestamp = object["timestamp"] as? NSNumber,
              let causal = object["causality"],
              let causalData = try? JSONSerialization.data(withJSONObject: causal),
              let snapshot = try? JSONDecoder().decode(CausalSnapshot.self, from: causalData),
              let kind = SyncMutation.Kind(rawValue: operation),
              let shape = SyncEntityShape.shapes[entityType] else { throw SyncMergeError.malformedMutation }
        let record = object["record"] as? [String: Any]
        guard kind == .delete || record != nil,
              record?["id"] as? String == entityID || kind == .delete,
              snapshot.changedFields.allSatisfy({ shape.columns[$0.fieldName] != nil }) else { throw SyncMergeError.malformedMutation }
        var values: [String: Data] = [:]
        for field in snapshot.changedFields {
            guard let value = record?[field.fieldName] else { throw SyncMergeError.malformedMutation }
            values[field.fieldName] = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
        }
        mutation = try SyncMutation(id: id, entityType: entityType, entityID: entityID,
                                    entityVersion: 1, timestampMS: timestamp.int64Value,
                                    kind: kind, fieldValues: values, causality: snapshot)
        self.payload = payload
    }

    static func journalPayload(for mutation: SyncMutation, decision: MergeDecision) throws -> Data {
        guard let shape = SyncEntityShape.shapes[mutation.entityType] else { throw SyncMergeError.malformedMutation }
        let record: Any
        if mutation.kind == .delete {
            record = NSNull()
        } else {
            var fields: [String: Any] = ["id": mutation.entityID]
            for field in decision.fields {
                guard shape.columns[field.name] != nil else { throw SyncMergeError.malformedMutation }
                fields[field.name] = try JSONSerialization.jsonObject(with: field.value, options: [.fragmentsAllowed])
            }
            guard Set(fields.keys).subtracting(["id"]) == Set(shape.columns.keys) else { throw SyncMergeError.malformedMutation }
            record = fields
        }
        let causal = try JSONSerialization.jsonObject(with: JSONEncoder().encode(mutation.journalCausality()))
        let object: [String: Any] = [
            "id": mutation.id, "deviceID": mutation.deviceID, "timestamp": mutation.timestampMS,
            "entityType": mutation.entityType, "entityID": mutation.entityID,
            "operation": mutation.kind.rawValue, "record": record, "causality": causal,
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

struct SyncEntityShape {
    let table: String
    let columns: [String: String]

    static let shapes: [String: SyncEntityShape] = [
        "profile": .init(table: "profile", columns: ["displayName": "display_name", "headline": "headline", "biography": "biography", "updatedAtMS": "updated_at_ms"]),
        "conversation": .init(table: "conversations", columns: ["title": "title", "createdAtMS": "created_at_ms", "updatedAtMS": "updated_at_ms"]),
        "message": .init(table: "messages", columns: ["conversationID": "conversation_id", "role": "role", "body": "body", "createdAtMS": "created_at_ms"]),
        "goal": .init(table: "goals", columns: ["title": "title", "detail": "detail", "status": "status", "createdAtMS": "created_at_ms", "updatedAtMS": "updated_at_ms"]),
        "milestone": .init(table: "milestones", columns: ["goalID": "goal_id", "title": "title", "status": "status", "targetAtMS": "target_at_ms", "updatedAtMS": "updated_at_ms"]),
        "action": .init(table: "actions", columns: ["goalID": "goal_id", "title": "title", "detail": "detail", "status": "status", "dueAtMS": "due_at_ms", "createdAtMS": "created_at_ms", "updatedAtMS": "updated_at_ms"]),
        "evidence": .init(table: "evidence", columns: ["goalID": "goal_id", "actionID": "action_id", "title": "title", "detail": "detail", "occurredAtMS": "occurred_at_ms", "createdAtMS": "created_at_ms"]),
        "memory": .init(table: "memory_items", columns: ["kind": "kind", "content": "content", "status": "status", "createdAtMS": "created_at_ms", "updatedAtMS": "updated_at_ms"]),
        "memory_source": .init(table: "memory_sources", columns: ["memoryItemID": "memory_item_id", "sourceType": "source_type", "sourceID": "source_id", "createdAtMS": "created_at_ms"]),
    ]

    static func materialize(_ decision: MergeDecision, entityType: String, entityID: String, in db: Database) throws {
        guard let shape = shapes[entityType] else { throw SyncMergeError.malformedMutation }
        let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(shape.table) WHERE id = ? COLLATE NOCASE", arguments: [entityID]) ?? 0
        guard count <= 1 else { throw SyncMergeError.persistenceFailed }
        if let deletion = decision.deletion {
            try db.execute(sql: "INSERT OR IGNORE INTO tombstones (id, entity_type, entity_id, deletion_version_id, deleted_at_ms) VALUES (?, ?, ?, ?, ?)", arguments: [UUID().uuidString, entityType, entityID, deletion.id, deletion.timestampMS])
            return
        }
        if decision.state.events.contains(where: { $0.kind == .resolve }) {
            // Only an explicit causally validated resolution can restore a
            // record hidden by a synchronized tombstone.
            try db.execute(sql: "DELETE FROM tombstones WHERE entity_type = ? AND entity_id = ? COLLATE NOCASE", arguments: [entityType, entityID])
        }
        if count == 0 {
            guard decision.state.events.contains(where: { $0.kind == .create }) else { return }
            let fields = Dictionary(uniqueKeysWithValues: decision.fields.map { ($0.name, $0.value) })
            guard Set(fields.keys) == Set(shape.columns.keys) else { return }
            let ordered = shape.columns.keys.sorted()
            let names = ["id"] + ordered.map { shape.columns[$0]! }
            let values = [entityID.databaseValue] + (try ordered.map { try databaseValue(fields[$0]!) })
            let placeholders = Array(repeating: "?", count: names.count).joined(separator: ", ")
            try db.execute(sql: "INSERT INTO \(shape.table) (\(names.joined(separator: ", "))) VALUES (\(placeholders))", arguments: StatementArguments(values))
        } else {
            let ordered = decision.fields.map(\.name).sorted()
            guard ordered.allSatisfy({ shape.columns[$0] != nil }) else { throw SyncMergeError.malformedMutation }
            if ordered.isEmpty { return }
            let fields = Dictionary(uniqueKeysWithValues: decision.fields.map { ($0.name, $0.value) })
            let assignments = ordered.map { "\(shape.columns[$0]!) = ?" }.joined(separator: ", ")
            let values = try ordered.map { try databaseValue(fields[$0]!) } + [entityID.databaseValue]
            try db.execute(sql: "UPDATE \(shape.table) SET \(assignments) WHERE id = ? COLLATE NOCASE", arguments: StatementArguments(values))
        }
    }

    static func retainCausality(_ mutation: SyncMutation, in db: Database) throws {
        for field in mutation.fields {
            try db.execute(sql: "INSERT OR IGNORE INTO field_versions (id, entity_type, entity_id, field_name, version_id, parent_version_id, device_id, device_counter, updated_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", arguments: [UUID().uuidString, mutation.entityType, mutation.entityID, field.name, mutation.id, field.ancestorVersionIDs.first, mutation.deviceID, mutation.counter, mutation.timestampMS])
        }
        try db.execute(sql: "INSERT OR IGNORE INTO field_versions (id, entity_type, entity_id, field_name, version_id, parent_version_id, device_id, device_counter, updated_at_ms) VALUES (?, ?, ?, '__record', ?, ?, ?, ?, ?)", arguments: [UUID().uuidString, mutation.entityType, mutation.entityID, mutation.id, mutation.recordParentVersionID, mutation.deviceID, mutation.counter, mutation.timestampMS])
    }

    private static func databaseValue(_ data: Data) throws -> DatabaseValue {
        let value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        switch value {
        case let text as String: return text.databaseValue
        case let number as NSNumber:
            guard number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue else { throw SyncMergeError.malformedMutation }
            return number.int64Value.databaseValue
        case _ as NSNull: return .null
        default: throw SyncMergeError.malformedMutation
        }
    }
}
