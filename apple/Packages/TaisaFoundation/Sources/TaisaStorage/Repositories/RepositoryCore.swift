import Foundation
import GRDB

public enum RepositoryError: Error, Sendable, Equatable {
    case invalidIdentifier
    case invalidTimestamp
    case alreadyExists
    case notFound
    case immutableRecord
    case mutationCollision
    case persistenceFailed
    case reservationMismatch
}

public protocol DomainRecord: Codable, Sendable, Equatable {
    var id: String { get }
}

/// Product code depends on this local contract; transport and database types
/// stay behind concrete repository implementations.
public protocol DomainRepository: Sendable {
    associatedtype Record: DomainRecord
    func get(id: String) async throws -> Record?
    func create(_ record: Record, context: MutationContext) async throws
    func update(_ record: Record, context: MutationContext) async throws
    func delete(id: String, context: MutationContext) async throws
}

extension ProfileRecord: DomainRecord {}
extension ConversationRecord: DomainRecord {}
extension MessageRecord: DomainRecord {}
extension GoalRecord: DomainRecord {}
extension MilestoneRecord: DomainRecord {}
extension ActionRecord: DomainRecord {}
extension EvidenceRecord: DomainRecord {}
extension MemoryRecord: DomainRecord {}
extension MemorySourceRecord: DomainRecord {}

struct RepositorySpec: Sendable {
    let table: String
    let entity: String
    let fields: [(property: String, column: String)]
    let immutable: Set<String>
    let appendOnly: Bool
}

/// The single repository/journal mapping from transport-neutral entity tags to
/// v1 storage tables and their identity-bearing parent references.
enum DomainEntity: String, CaseIterable {
    case profile, conversation, message, goal, milestone, action, evidence, memory, memory_source

    var table: String {
        switch self {
        case .profile: "profile"
        case .conversation: "conversations"
        case .message: "messages"
        case .goal: "goals"
        case .milestone: "milestones"
        case .action: "actions"
        case .evidence: "evidence"
        case .memory: "memory_items"
        case .memory_source: "memory_sources"
        }
    }

    var references: [(property: String, column: String, table: String)] {
        switch self {
        case .message: [("conversationID", "conversation_id", "conversations")]
        case .milestone: [("goalID", "goal_id", "goals")]
        case .action: [("goalID", "goal_id", "goals")]
        case .evidence: [("goalID", "goal_id", "goals"), ("actionID", "action_id", "actions")]
        case .memory_source: [("memoryItemID", "memory_item_id", "memory_items")]
        default: []
        }
    }
}

struct RepositoryCore<Record: DomainRecord>: Sendable {
    let store: TaisaStore
    let spec: RepositorySpec

    func get(id: String) async throws -> Record? {
        let id = try canonicalID(id)
        do {
            return try await store.read { db in
                let matches = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(spec.table) WHERE id = ? COLLATE NOCASE", arguments: [id]) ?? 0
                guard matches <= 1 else { throw RepositoryError.persistenceFailed }
                guard let row = try Row.fetchOne(db, sql: "SELECT * FROM \(spec.table) WHERE id = ? COLLATE NOCASE AND NOT EXISTS (SELECT 1 FROM tombstones WHERE entity_type = ? AND entity_id = ? COLLATE NOCASE)", arguments: [id, spec.entity, id]) else { return nil }
                return try decode(row)
            }
        } catch {
            throw RepositoryError.persistenceFailed
        }
    }

    func create(_ record: Record, context: MutationContext) async throws {
        let record = try canonicalRecord(record), context = try canonicalContext(context)
        try validate(record: record, context: context)
        try await safeWrite { db in
            let fields = try properties(record)
            let storedFields = try storageFields(fields, db: db)
            if try isDuplicate(context, entityID: record.id, operation: "create", record: record, db: db) { return }
            try validateSourceTuple(fields, excluding: nil, db: db)
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(spec.table) WHERE id = ? COLLATE NOCASE", arguments: [record.id]) == 0 else { throw RepositoryError.alreadyExists }
            let columns = spec.fields.map(\.column)
            let placeholders = Array(repeating: "?", count: columns.count).joined(separator: ", ")
            try db.execute(sql: "INSERT INTO \(spec.table) (\(columns.joined(separator: ", "))) VALUES (\(placeholders))", arguments: StatementArguments(columns.map { value(storedFields, for: $0) }))
            let causality = try versions(fields: fields, previous: [:], id: record.id, context: context, db: db)
            try ChangeJournal.insert(db: db, context: context, entity: spec.entity, entityID: record.id, operation: "create", record: record, causality: causality)
        }
    }

    func update(_ record: Record, context: MutationContext) async throws {
        let record = try canonicalRecord(record), context = try canonicalContext(context)
        guard !spec.appendOnly else { throw RepositoryError.immutableRecord }
        try validate(record: record, context: context)
        try await safeWrite { db in
            let fields = try properties(record)
            let storedFields = try storageFields(fields, db: db)
            if try isDuplicate(context, entityID: record.id, operation: "update", record: record, db: db) { return }
            try validateSourceTuple(fields, excluding: record.id, db: db)
            let matches = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(spec.table) WHERE id = ? COLLATE NOCASE", arguments: [record.id]) ?? 0
            guard matches <= 1 else { throw RepositoryError.persistenceFailed }
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM \(spec.table) WHERE id = ? COLLATE NOCASE", arguments: [record.id]),
                  try !isDeleted(record.id, db: db) else { throw RepositoryError.notFound }
            let old = try properties(decode(row))
            for key in spec.immutable where !equal(fields[key], old[key]) { throw RepositoryError.immutableRecord }
            let changed = spec.fields.filter { $0.property != "id" && !equal(fields[$0.property], old[$0.property]) }
            if !changed.isEmpty {
                let assignments = changed.map { "\($0.column) = ?" }.joined(separator: ", ")
                let args = changed.map { value(storedFields, for: $0.column) } + [record.id.databaseValue]
                try db.execute(sql: "UPDATE \(spec.table) SET \(assignments) WHERE id = ? COLLATE NOCASE", arguments: StatementArguments(args))
            }
            let causality = try versions(fields: fields, previous: old, id: record.id, context: context, db: db)
            try ChangeJournal.insert(db: db, context: context, entity: spec.entity, entityID: record.id, operation: "update", record: record, causality: causality)
        }
    }

    func delete(id: String, context: MutationContext) async throws {
        let id = try canonicalID(id), context = try canonicalContext(context)
        try validateID(id); try validate(context)
        try await safeWrite { db in
            if try isDuplicate(context, entityID: id, operation: "delete", record: Optional<Record>.none, db: db) { return }
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(spec.table) WHERE id = ? COLLATE NOCASE", arguments: [id]) == 1,
                  try !isDeleted(id, db: db) else { throw RepositoryError.notFound }
            let causality = try versions(fields: [:], previous: [:], id: id, context: context, db: db)
            try db.execute(sql: "INSERT INTO tombstones (id, entity_type, entity_id, deletion_version_id, deleted_at_ms) VALUES (?, ?, ?, ?, ?)", arguments: [UUID().uuidString, spec.entity, id, context.id, context.timestamp])
            try ChangeJournal.insert(db: db, context: context, entity: spec.entity, entityID: id, operation: "delete", record: Optional<Record>.none, causality: causality)
        }
    }

    private func safeWrite(_ body: @Sendable (Database) throws -> Void) async throws {
        do {
            try await store.write(body)
        } catch let error as RepositoryError {
            throw error
        } catch {
            throw RepositoryError.persistenceFailed
        }
    }

    private func isDeleted(_ id: String, db: Database) throws -> Bool {
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tombstones WHERE entity_type = ? AND entity_id = ? COLLATE NOCASE", arguments: [spec.entity, id]) == 1
    }

    private func isDuplicate(_ context: MutationContext, entityID: String, operation: String, record: Record?, db: Database) throws -> Bool {
        let matches = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM outbox WHERE mutation_id = ? COLLATE NOCASE", arguments: [context.id]) ?? 0
        guard matches <= 1 else { throw RepositoryError.persistenceFailed }
        guard let row = try Row.fetchOne(db, sql: "SELECT entity_type, entity_id, payload FROM outbox WHERE mutation_id = ? COLLATE NOCASE", arguments: [context.id]) else { return false }
        let storedPayload: Data = row["payload"]
        let causality = try ChangeJournal.causality(from: storedPayload)
        let payload = try ChangeJournal.canonicalPayload(context: context, entity: spec.entity, entityID: entityID, operation: operation, record: record, causality: causality)
        guard (row["entity_type"] as String) == spec.entity,
              try canonicalID(row["entity_id"] as String) == entityID,
              try ChangeJournal.normalizedPayload(storedPayload).data == ChangeJournal.normalizedPayload(payload).data else { throw RepositoryError.mutationCollision }
        return true
    }

    private func validate(record: Record, context: MutationContext) throws {
        try validateID(record.id); try validate(context)
    }

    private func validate(_ context: MutationContext) throws {
        try validateID(context.id); try validateID(context.deviceID)
        guard context.timestamp >= 0 else { throw RepositoryError.invalidTimestamp }
    }

    private func validateID(_ id: String) throws {
        _ = try canonicalID(id)
    }

    private func canonicalID(_ id: String) throws -> String {
        guard let canonical = UUIDIdentity.canonical(id) else { throw RepositoryError.invalidIdentifier }
        return canonical
    }

    private func canonicalContext(_ context: MutationContext) throws -> MutationContext {
        MutationContext(id: try canonicalID(context.id), deviceID: try canonicalID(context.deviceID), timestamp: context.timestamp)
    }

    private func canonicalRecord(_ record: Record) throws -> Record {
        let data = try JSONEncoder().encode(record)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw RepositoryError.persistenceFailed }
        for (property, _) in spec.fields where property == "id" || property.hasSuffix("ID") {
            if let raw = object[property] as? String { object[property] = try canonicalID(raw) }
        }
        return try JSONDecoder().decode(Record.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func properties(_ record: Record) throws -> [String: Any] {
        let data = try JSONEncoder().encode(record)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private func storageFields(_ fields: [String: Any], db: Database) throws -> [String: Any] {
        guard let kind = DomainEntity(rawValue: spec.entity), kind.table == spec.table else { throw RepositoryError.persistenceFailed }
        var stored = fields
        for (property, _, table) in kind.references {
            guard let canonical = fields[property] as? String else { continue }
            let matches = try String.fetchAll(db, sql: "SELECT id FROM \(table) WHERE id = ? COLLATE NOCASE", arguments: [canonical])
            guard matches.count <= 1 else { throw RepositoryError.persistenceFailed }
            if let existing = matches.first { stored[property] = existing }
        }
        return stored
    }

    private func validateSourceTuple(_ fields: [String: Any], excluding ownID: String?, db: Database) throws {
        guard spec.entity == "memory_source" else { return }
        guard let memoryID = fields["memoryItemID"] as? String,
              let sourceType = fields["sourceType"] as? String,
              let sourceID = fields["sourceID"] as? String else { throw RepositoryError.persistenceFailed }
        // V1's composite UNIQUE uses BINARY UUID strings. Preserve its
        // semantic relationship uniqueness for previously persisted casing.
        let matches = try String.fetchAll(db, sql: "SELECT id FROM memory_sources WHERE source_type = ? AND source_id = ? COLLATE NOCASE AND memory_item_id = ? COLLATE NOCASE", arguments: [sourceType, sourceID, memoryID])
        guard matches.allSatisfy({ ownID != nil && UUIDIdentity.canonical($0) == ownID }) else { throw RepositoryError.persistenceFailed }
    }

    private func decode(_ row: Row) throws -> Record {
        var object: [String: Any] = [:]
        for (property, column) in spec.fields {
            let value: DatabaseValue = row[column]
            if value.isNull { object[property] = NSNull() }
            else if let text = String.fromDatabaseValue(value) { object[property] = text }
            else if let integer = Int64.fromDatabaseValue(value) { object[property] = integer }
        }
        return try canonicalRecord(JSONDecoder().decode(Record.self, from: JSONSerialization.data(withJSONObject: object)))
    }

    private func value(_ fields: [String: Any], for column: String) -> DatabaseValue {
        guard let property = spec.fields.first(where: { $0.column == column })?.property,
              let raw = fields[property], !(raw is NSNull) else { return .null }
        if let text = raw as? String { return text.databaseValue }
        if let number = raw as? NSNumber { return number.int64Value.databaseValue }
        return .null
    }

    private func equal(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil), (_ as NSNull, _ as NSNull): return true
        case (let x as String, let y as String): return x == y
        case (let x as NSNumber, let y as NSNumber): return x == y
        default: return false
        }
    }

    private func versions(fields: [String: Any], previous: [String: Any], id: String, context: MutationContext, db: Database) throws -> CausalSnapshot {
        let recordParent = try latestVersion(field: "__record", id: id, db: db)
        let previousCounter = try Int64.fetchOne(db, sql: "SELECT MAX(device_counter) FROM field_versions WHERE device_id = ? COLLATE NOCASE", arguments: [context.deviceID]) ?? 0
        let (counter, overflow) = previousCounter.addingReportingOverflow(1)
        guard !overflow else { throw RepositoryError.persistenceFailed }
        var observed: [ObservedFieldVersion] = []
        var changed: [FieldCausalVersion] = []
        let visibleTips = try visibleFieldTips(id: id, db: db)
        for (property, _) in spec.fields where property != "id" && property != "createdAtMS" {
            let parent = try latestVersion(field: property, id: id, db: db)
            if let parent { observed.append(ObservedFieldVersion(fieldName: property, versionID: parent)) }
            guard fields[property] != nil || previous[property] != nil,
                  !equal(fields[property], previous[property]) else { continue }
            var ancestors: [String] = []
            var pending = Array(Set(visibleTips[property] ?? []).subtracting(parent.map { [$0] } ?? [])).sorted()
            if let parent { pending.append(parent) }
            var walked: Set<String> = []
            var listed: Set<String> = []
            while let version = pending.popLast(), walked.insert(version).inserted {
                if listed.insert(version).inserted { ancestors.append(version) }
                // A resolution may have multiple parents. The v1 field_versions
                // row records its immediate parent; the committed journal
                // snapshot retains the remaining transitive branches.
                let historical = try Row.fetchAll(db, sql: "SELECT mutation_id, entity_type, entity_id, payload FROM outbox WHERE mutation_id = ? COLLATE NOCASE", arguments: [version])
                guard historical.count <= 1 else { throw RepositoryError.persistenceFailed }
                if let row = historical.first {
                    guard try canonicalID(row["mutation_id"] as String) == version,
                          (row["entity_type"] as String) == spec.entity,
                          try canonicalID(row["entity_id"] as String) == id else { throw RepositoryError.persistenceFailed }
                    let payload: Data = row["payload"]
                    let snapshot = try ChangeJournal.causality(from: payload)
                    guard try canonicalID(snapshot.logicalVersionID) == version else { throw RepositoryError.persistenceFailed }
                    let matching = snapshot.changedFields.filter { $0.fieldName == property }
                    guard matching.count <= 1 else { throw RepositoryError.persistenceFailed }
                    let retained = snapshot.retainedDeletionCausality?.fieldAncestry?[property] ?? []
                    let historicalParents: [String]
                    if let field = matching.first {
                        guard try canonicalID(field.versionID) == version,
                              field.deviceCounter == snapshot.deviceCounter else { throw RepositoryError.persistenceFailed }
                        historicalParents = field.ancestorVersionIDs + retained
                    } else {
                        guard !retained.isEmpty,
                              let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
                              object["operation"] as? String == "delete" else { throw RepositoryError.persistenceFailed }
                        historicalParents = retained
                    }
                    for raw in historicalParents {
                        let ancestor = try canonicalID(raw)
                        if listed.insert(ancestor).inserted { ancestors.append(ancestor) }
                    }
                }
                if let ancestor = try String.fetchOne(db, sql: "SELECT parent_version_id FROM field_versions WHERE entity_type = ? AND entity_id = ? COLLATE NOCASE AND field_name = ? AND version_id = ? COLLATE NOCASE ORDER BY rowid DESC LIMIT 1", arguments: [spec.entity, id, property, version]) {
                    pending.append(try canonicalID(ancestor))
                }
            }
            try db.execute(sql: "INSERT INTO field_versions (id, entity_type, entity_id, field_name, version_id, parent_version_id, device_id, device_counter, updated_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", arguments: [UUID().uuidString, spec.entity, id, property, context.id, parent, context.deviceID, counter, context.timestamp])
            changed.append(FieldCausalVersion(fieldName: property, versionID: context.id, parentVersionID: parent, ancestorVersionIDs: ancestors, deviceCounter: counter))
        }
        try db.execute(sql: "INSERT INTO field_versions (id, entity_type, entity_id, field_name, version_id, parent_version_id, device_id, device_counter, updated_at_ms) VALUES (?, ?, ?, '__record', ?, ?, ?, ?, ?)", arguments: [UUID().uuidString, spec.entity, id, context.id, recordParent, context.deviceID, counter, context.timestamp])
        return CausalSnapshot(logicalVersionID: context.id, recordParentVersionID: recordParent, deviceID: context.deviceID, deviceCounter: counter, changedFields: changed.sorted { $0.fieldName < $1.fieldName }, observedFieldVersions: observed.sorted { $0.fieldName < $1.fieldName })
    }

    private func latestVersion(field: String, id: String, db: Database) throws -> String? {
        try String.fetchOne(db, sql: "SELECT version_id FROM field_versions WHERE entity_type = ? AND entity_id = ? COLLATE NOCASE AND field_name = ? ORDER BY rowid DESC LIMIT 1", arguments: [spec.entity, id, field]).map { try canonicalID($0) }
    }

    private func visibleFieldTips(id: String, db: Database) throws -> [String: [String]] {
        guard let encoded = try Data.fetchOne(db, sql: "SELECT engine_state FROM sync_state WHERE id = 1") else { return [:] }
        guard let state = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else { throw RepositoryError.persistenceFailed }
        let map = state["visibleFieldTips"] as? [String: [String]] ?? [:]
        let prefix = spec.entity + "|" + id + "|"
        var result: [String: [String]] = [:]
        for (key, versions) in map where key.hasPrefix(prefix) {
            let property = String(key.dropFirst(prefix.count))
            guard spec.fields.contains(where: { $0.property == property }) else { throw RepositoryError.persistenceFailed }
            result[property] = try versions.map { try canonicalID($0) }
        }
        return result
    }
}
