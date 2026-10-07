import Foundation
import GRDB
import TaisaStorage

enum SyncProjectionError: Error { case dependencyPending }

struct SyncEngineCheckpoint: Codable, Sendable {
    var cloudKitState: Data?
    var cloudKitInbox: [CloudKitInboxItem] = []
    var cloudKitNextSequence: Int64 = 0
    var received: [String: Data] = [:]
    var retryAtMS: Int64?
    var retryAttempts: Int = 0
    var recoveryState: SyncState?
    var lastState: SyncState?
    var recoveryPrepared: Bool = false
    var turnGeneration: Int64 = 0
    var visibleFieldTips: [String: [String]] = [:]

    private enum CodingKeys: String, CodingKey { case received, retryAtMS, retryAttempts, recoveryState, lastState, recoveryPrepared, turnGeneration, visibleFieldTips, cloudKitState, cloudKitInbox, cloudKitNextSequence }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        received = try values.decodeIfPresent([String: Data].self, forKey: .received) ?? [:]
        retryAtMS = try values.decodeIfPresent(Int64.self, forKey: .retryAtMS)
        retryAttempts = try values.decodeIfPresent(Int.self, forKey: .retryAttempts) ?? 0
        recoveryState = try values.decodeIfPresent(SyncState.self, forKey: .recoveryState)
        lastState = try values.decodeIfPresent(SyncState.self, forKey: .lastState)
        recoveryPrepared = try values.decodeIfPresent(Bool.self, forKey: .recoveryPrepared) ?? false
        turnGeneration = try values.decodeIfPresent(Int64.self, forKey: .turnGeneration) ?? 0
        visibleFieldTips = try values.decodeIfPresent([String: [String]].self, forKey: .visibleFieldTips) ?? [:]
        cloudKitState = try values.decodeIfPresent(Data.self, forKey: .cloudKitState)
        cloudKitInbox = try values.decodeIfPresent([CloudKitInboxItem].self, forKey: .cloudKitInbox) ?? []
        cloudKitNextSequence = try values.decodeIfPresent(Int64.self, forKey: .cloudKitNextSequence) ?? 0
    }
}

struct CloudKitInboxItem: Codable, Sendable {
    let sequence: Int64
    let change: EncryptedChange
}

/// The journal's canonical payload is the only plaintext wire input. All of
/// these projections live inside SQLCipher or transient memory.
struct SyncProjection {
    let mutation: SyncMutation
    let payload: Data
    let fullFields: [String: Data]

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
        let complete = try kind == .delete ? [:] : shape.completeFields(record!)
        var values: [String: Data] = [:]
        for field in snapshot.changedFields {
            guard let value = complete[field.fieldName] else { throw SyncMergeError.malformedMutation }
            values[field.fieldName] = value
        }
        mutation = try SyncMutation(id: id, entityType: entityType, entityID: entityID,
                                    entityVersion: 1, timestampMS: timestamp.int64Value,
                                    kind: kind, fieldValues: values, causality: snapshot)
        self.payload = payload
        self.fullFields = complete
    }

    static func journalPayload(for mutation: SyncMutation, decision: MergeDecision, fullFields: [String: Data]) throws -> Data {
        guard let shape = SyncEntityShape.shapes[mutation.entityType] else { throw SyncMergeError.malformedMutation }
        let record: Any
        if mutation.kind == .delete {
            record = NSNull()
        } else {
            var fields: [String: Any] = ["id": mutation.entityID]
            for (name, value) in fullFields {
                guard shape.columns[name] != nil else { throw SyncMergeError.malformedMutation }
                fields[name] = try JSONSerialization.jsonObject(with: value, options: [.fragmentsAllowed])
            }
            for field in decision.fields {
                guard shape.columns[field.name] != nil else { throw SyncMergeError.malformedMutation }
                fields[field.name] = try JSONSerialization.jsonObject(with: field.value, options: [.fragmentsAllowed])
            }
            guard Set(fields.keys).subtracting(["id"]) == Set(shape.columns.keys) else { throw SyncMergeError.malformedMutation }
            _ = try shape.completeFields(fields)
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
    let optional: Set<String>

    init(table: String, columns: [String: String], optional: Set<String> = []) {
        self.table = table
        self.columns = columns
        self.optional = optional
    }

    static let shapes: [String: SyncEntityShape] = [
        "profile": .init(table: "profile", columns: ["displayName": "display_name", "headline": "headline", "biography": "biography", "updatedAtMS": "updated_at_ms"], optional: []),
        "conversation": .init(table: "conversations", columns: ["title": "title", "createdAtMS": "created_at_ms", "updatedAtMS": "updated_at_ms"]),
        "message": .init(table: "messages", columns: ["conversationID": "conversation_id", "role": "role", "body": "body", "createdAtMS": "created_at_ms"]),
        "goal": .init(table: "goals", columns: ["title": "title", "detail": "detail", "status": "status", "createdAtMS": "created_at_ms", "updatedAtMS": "updated_at_ms"]),
        "milestone": .init(table: "milestones", columns: ["goalID": "goal_id", "title": "title", "status": "status", "targetAtMS": "target_at_ms", "updatedAtMS": "updated_at_ms"], optional: ["targetAtMS"]),
        "action": .init(table: "actions", columns: ["goalID": "goal_id", "title": "title", "detail": "detail", "status": "status", "dueAtMS": "due_at_ms", "createdAtMS": "created_at_ms", "updatedAtMS": "updated_at_ms"], optional: ["goalID", "dueAtMS"]),
        "evidence": .init(table: "evidence", columns: ["goalID": "goal_id", "actionID": "action_id", "title": "title", "detail": "detail", "occurredAtMS": "occurred_at_ms", "createdAtMS": "created_at_ms"], optional: ["goalID", "actionID"]),
        "memory": .init(table: "memory_items", columns: ["kind": "kind", "content": "content", "status": "status", "createdAtMS": "created_at_ms", "updatedAtMS": "updated_at_ms"]),
        "memory_source": .init(table: "memory_sources", columns: ["memoryItemID": "memory_item_id", "sourceType": "source_type", "sourceID": "source_id", "createdAtMS": "created_at_ms"]),
        // Local audio identity, fingerprint, duration, and cleanup queue are intentionally
        // absent. They are device-owned and never enter a sync mutation.
        "voice_turn": .init(table: "voice_turns", columns: [
            "conversationID": "conversation_id",
            "transcriptionRequestID": "transcription_request_id",
            "transcriptionIdempotencyKey": "transcription_idempotency_key",
            "coachingRequestID": "coaching_request_id",
            "coachingIdempotencyKey": "coaching_idempotency_key",
            "state": "state", "stage": "stage",
            "acceptedTranscript": "accepted_transcript",
            "uncertainTranscript": "uncertain_transcript",
            "retryCount": "retry_count", "nextRetryAtMS": "next_retry_at_ms",
            "failureCode": "failure_code",
            "transcriptionReceipt": "transcription_receipt",
            "coachingReceipt": "coaching_receipt",
            "userMessageID": "user_message_id",
            "assistantMessageID": "assistant_message_id",
            "cleanupState": "cleanup_state",
            "createdAtMS": "created_at_ms", "updatedAtMS": "updated_at_ms",
        ], optional: [
            "acceptedTranscript", "uncertainTranscript", "nextRetryAtMS", "failureCode",
            "transcriptionReceipt", "coachingReceipt", "userMessageID", "assistantMessageID",
        ]),
    ]

    func completeFields(_ record: [String: Any]) throws -> [String: Data] {
        guard Set(record.keys).isSubset(of: Set(columns.keys).union(["id"])),
              record["id"] is String else { throw SyncMergeError.malformedMutation }
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        do {
            switch table {
            case "profile": _ = try JSONDecoder().decode(ProfileRecord.self, from: data)
            case "conversations": _ = try JSONDecoder().decode(ConversationRecord.self, from: data)
            case "messages": _ = try JSONDecoder().decode(MessageRecord.self, from: data)
            case "goals": _ = try JSONDecoder().decode(GoalRecord.self, from: data)
            case "milestones": _ = try JSONDecoder().decode(MilestoneRecord.self, from: data)
            case "actions": _ = try JSONDecoder().decode(ActionRecord.self, from: data)
            case "evidence": _ = try JSONDecoder().decode(EvidenceRecord.self, from: data)
            case "memory_items": _ = try JSONDecoder().decode(MemoryRecord.self, from: data)
            case "memory_sources": _ = try JSONDecoder().decode(MemorySourceRecord.self, from: data)
            case "voice_turns": _ = try JSONDecoder().decode(VoiceTurnRecord.self, from: data)
            default: throw SyncMergeError.malformedMutation
            }
        } catch { throw SyncMergeError.malformedMutation }
        var result: [String: Data] = [:]
        for name in columns.keys {
            let value: Any
            if let present = record[name] { value = present }
            else if optional.contains(name) { value = NSNull() }
            else { throw SyncMergeError.malformedMutation }
            result[name] = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
        }
        return result
    }

    static func materialize(_ decision: MergeDecision, entityType: String, entityID: String, source: [SyncProjection], in db: Database) throws {
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
            guard decision.state.events.contains(where: { $0.kind == .create }) else { throw SyncProjectionError.dependencyPending }
            guard let creation = source.first(where: { $0.mutation.kind == .create && $0.mutation.entityType == entityType && $0.mutation.entityID == entityID }) else { throw SyncMergeError.malformedMutation }
            var fields = creation.fullFields
            for field in decision.fields { fields[field.name] = field.value }
            guard Set(fields.keys) == Set(shape.columns.keys) else { throw SyncMergeError.malformedMutation }
            try checkParents(in: fields, shape: shape, db: db)
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
            try checkParents(in: fields, shape: shape, db: db)
            let assignments = ordered.map { "\(shape.columns[$0]!) = ?" }.joined(separator: ", ")
            let values = try ordered.map { try databaseValue(fields[$0]!) } + [entityID.databaseValue]
            try db.execute(sql: "UPDATE \(shape.table) SET \(assignments) WHERE id = ? COLLATE NOCASE", arguments: StatementArguments(values))
        }
    }

    private static func checkParents(in fields: [String: Data], shape: SyncEntityShape, db: Database) throws {
        let relations: [(String, String)] = switch shape.table {
        case "messages": [("conversationID", "conversations")]
        case "milestones": [("goalID", "goals")]
        case "actions": [("goalID", "goals")]
        case "evidence": [("goalID", "goals"), ("actionID", "actions")]
        case "memory_sources": [("memoryItemID", "memory_items")]
        case "voice_turns": [
            ("conversationID", "conversations"),
            ("userMessageID", "messages"),
            ("assistantMessageID", "messages"),
        ]
        default: []
        }
        for (property, parentTable) in relations {
            guard let encoded = fields[property],
                  let parent = try JSONSerialization.jsonObject(with: encoded, options: [.fragmentsAllowed]) as? String else { continue }
            let exists = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(parentTable) WHERE id = ? COLLATE NOCASE", arguments: [parent]) ?? 0
            guard exists == 1 else { throw SyncProjectionError.dependencyPending }
        }
    }

    static func retainCausality(_ mutation: SyncMutation, in db: Database) throws {
        for field in mutation.fields {
            try db.execute(sql: "INSERT OR IGNORE INTO field_versions (id, entity_type, entity_id, field_name, version_id, parent_version_id, device_id, device_counter, updated_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", arguments: [UUID().uuidString, mutation.entityType, mutation.entityID, field.name, mutation.id, field.ancestorVersionIDs.first, mutation.deviceID, mutation.counter, mutation.timestampMS])
        }
        try db.execute(sql: "INSERT OR IGNORE INTO field_versions (id, entity_type, entity_id, field_name, version_id, parent_version_id, device_id, device_counter, updated_at_ms) VALUES (?, ?, ?, '__record', ?, ?, ?, ?, ?)", arguments: [UUID().uuidString, mutation.entityType, mutation.entityID, mutation.id, mutation.recordParentVersionID, mutation.deviceID, mutation.counter, mutation.timestampMS])
    }

    /// RepositoryCore reads the highest rowid as its visible parent. Reorder
    /// only the validated winners after retaining every historical edge.
    static func retainVisibleTips(_ decision: MergeDecision, entityType: String, entityID: String, in db: Database) throws {
        for field in decision.fields {
            try promote(field: field.name, version: field.versionID, entityType: entityType, entityID: entityID, in: db)
        }
        let events = decision.state.events
        let byID = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
        func ancestors(of event: SyncMutation) -> Set<String> {
            var seen: Set<String> = []
            var pending = (event.recordParentVersionID.map { [$0] } ?? []) + (event.resolvedParentVersionIDs ?? [])
            while let id = pending.popLast() {
                guard seen.insert(id).inserted, let parent = byID[id] else { continue }
                pending += (parent.recordParentVersionID.map { [$0] } ?? []) + (parent.resolvedParentVersionIDs ?? [])
            }
            return seen
        }
        let inherited = Set(events.flatMap { ancestors(of: $0) })
        guard let tip = events.filter({ !inherited.contains($0.id) }).max(by: { $0.id < $1.id }) else { throw SyncMergeError.malformedMutation }
        try promote(field: "__record", version: tip.id, entityType: entityType, entityID: entityID, in: db)
    }

    private static func promote(field: String, version: String, entityType: String, entityID: String, in db: Database) throws {
        guard let row = try Row.fetchOne(db, sql: "SELECT id, parent_version_id, device_id, device_counter, updated_at_ms FROM field_versions WHERE entity_type = ? AND entity_id = ? COLLATE NOCASE AND field_name = ? AND version_id = ? COLLATE NOCASE", arguments: [entityType, entityID, field, version]) else { throw SyncMergeError.persistenceFailed }
        let id: String = row["id"]
        let parent: String? = row["parent_version_id"]
        let device: String = row["device_id"]
        let counter: Int64 = row["device_counter"]
        let timestamp: Int64 = row["updated_at_ms"]
        try db.execute(sql: "DELETE FROM field_versions WHERE id = ?", arguments: [id])
        try db.execute(sql: "INSERT INTO field_versions (id, entity_type, entity_id, field_name, version_id, parent_version_id, device_id, device_counter, updated_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", arguments: [id, entityType, entityID, field, version, parent, device, counter, timestamp])
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
