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

struct RepositoryCore<Record: DomainRecord>: Sendable {
    let store: TaisaStore
    let spec: RepositorySpec

    func get(id: String) async throws -> Record? {
        try validateID(id)
        do {
            return try await store.read { db in
                guard let row = try Row.fetchOne(db, sql: "SELECT * FROM \(spec.table) WHERE id = ? AND NOT EXISTS (SELECT 1 FROM tombstones WHERE entity_type = ? AND entity_id = ?)", arguments: [id, spec.entity, id]) else { return nil }
                return try decode(row)
            }
        } catch {
            throw RepositoryError.persistenceFailed
        }
    }

    func create(_ record: Record, context: MutationContext) async throws {
        try validate(record: record, context: context)
        try await safeWrite { db in
            let fields = try properties(record)
            if try isDuplicate(context, entityID: record.id, operation: "create", record: record, db: db) { return }
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(spec.table) WHERE id = ?", arguments: [record.id]) == 0 else { throw RepositoryError.alreadyExists }
            let columns = spec.fields.map(\.column)
            let placeholders = Array(repeating: "?", count: columns.count).joined(separator: ", ")
            try db.execute(sql: "INSERT INTO \(spec.table) (\(columns.joined(separator: ", "))) VALUES (\(placeholders))", arguments: StatementArguments(columns.map { value(fields, for: $0) }))
            let causality = try versions(fields: fields, previous: [:], id: record.id, context: context, db: db)
            try ChangeJournal.insert(db: db, context: context, entity: spec.entity, entityID: record.id, operation: "create", record: record, causality: causality)
        }
    }

    func update(_ record: Record, context: MutationContext) async throws {
        guard !spec.appendOnly else { throw RepositoryError.immutableRecord }
        try validate(record: record, context: context)
        try await safeWrite { db in
            let fields = try properties(record)
            if try isDuplicate(context, entityID: record.id, operation: "update", record: record, db: db) { return }
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM \(spec.table) WHERE id = ?", arguments: [record.id]),
                  try !isDeleted(record.id, db: db) else { throw RepositoryError.notFound }
            let old = try properties(decode(row))
            for key in spec.immutable where !equal(fields[key], old[key]) { throw RepositoryError.immutableRecord }
            let changed = spec.fields.filter { $0.property != "id" && !equal(fields[$0.property], old[$0.property]) }
            if !changed.isEmpty {
                let assignments = changed.map { "\($0.column) = ?" }.joined(separator: ", ")
                let args = changed.map { value(fields, for: $0.column) } + [record.id.databaseValue]
                try db.execute(sql: "UPDATE \(spec.table) SET \(assignments) WHERE id = ?", arguments: StatementArguments(args))
            }
            let causality = try versions(fields: fields, previous: old, id: record.id, context: context, db: db)
            try ChangeJournal.insert(db: db, context: context, entity: spec.entity, entityID: record.id, operation: "update", record: record, causality: causality)
        }
    }

    func delete(id: String, context: MutationContext) async throws {
        try validateID(id); try validate(context)
        try await safeWrite { db in
            if try isDuplicate(context, entityID: id, operation: "delete", record: Optional<Record>.none, db: db) { return }
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(spec.table) WHERE id = ?", arguments: [id]) == 1,
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
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tombstones WHERE entity_type = ? AND entity_id = ?", arguments: [spec.entity, id]) == 1
    }

    private func isDuplicate(_ context: MutationContext, entityID: String, operation: String, record: Record?, db: Database) throws -> Bool {
        guard let row = try Row.fetchOne(db, sql: "SELECT entity_type, entity_id, payload FROM outbox WHERE mutation_id = ?", arguments: [context.id]) else { return false }
        let storedPayload: Data = row["payload"]
        let causality = try ChangeJournal.causality(from: storedPayload)
        let payload = try ChangeJournal.canonicalPayload(context: context, entity: spec.entity, entityID: entityID, operation: operation, record: record, causality: causality)
        guard (row["entity_type"] as String) == spec.entity,
              (row["entity_id"] as String) == entityID,
              storedPayload == payload else { throw RepositoryError.mutationCollision }
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
        guard id.count == 36, UUID(uuidString: id) != nil else { throw RepositoryError.invalidIdentifier }
    }

    private func properties(_ record: Record) throws -> [String: Any] {
        let data = try JSONEncoder().encode(record)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private func decode(_ row: Row) throws -> Record {
        var object: [String: Any] = [:]
        for (property, column) in spec.fields {
            let value: DatabaseValue = row[column]
            if value.isNull { object[property] = NSNull() }
            else if let text = String.fromDatabaseValue(value) { object[property] = text }
            else if let integer = Int64.fromDatabaseValue(value) { object[property] = integer }
        }
        return try JSONDecoder().decode(Record.self, from: JSONSerialization.data(withJSONObject: object))
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
        let previousCounter = try Int64.fetchOne(db, sql: "SELECT MAX(device_counter) FROM field_versions WHERE device_id = ?", arguments: [context.deviceID]) ?? 0
        let (counter, overflow) = previousCounter.addingReportingOverflow(1)
        guard !overflow else { throw RepositoryError.persistenceFailed }
        var observed: [ObservedFieldVersion] = []
        var changed: [FieldCausalVersion] = []
        for (property, _) in spec.fields where property != "id" && property != "createdAtMS" {
            let parent = try latestVersion(field: property, id: id, db: db)
            if let parent { observed.append(ObservedFieldVersion(fieldName: property, versionID: parent)) }
            guard fields[property] != nil || previous[property] != nil,
                  !equal(fields[property], previous[property]) else { continue }
            var ancestors: [String] = []
            var cursor = parent
            var seen: Set<String> = []
            while let version = cursor, seen.insert(version).inserted {
                ancestors.append(version)
                cursor = try String.fetchOne(db, sql: "SELECT parent_version_id FROM field_versions WHERE entity_type = ? AND entity_id = ? AND field_name = ? AND version_id = ? ORDER BY rowid DESC LIMIT 1", arguments: [spec.entity, id, property, version])
            }
            try db.execute(sql: "INSERT INTO field_versions (id, entity_type, entity_id, field_name, version_id, parent_version_id, device_id, device_counter, updated_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", arguments: [UUID().uuidString, spec.entity, id, property, context.id, parent, context.deviceID, counter, context.timestamp])
            changed.append(FieldCausalVersion(fieldName: property, versionID: context.id, parentVersionID: parent, ancestorVersionIDs: ancestors, deviceCounter: counter))
        }
        try db.execute(sql: "INSERT INTO field_versions (id, entity_type, entity_id, field_name, version_id, parent_version_id, device_id, device_counter, updated_at_ms) VALUES (?, ?, ?, '__record', ?, ?, ?, ?, ?)", arguments: [UUID().uuidString, spec.entity, id, context.id, recordParent, context.deviceID, counter, context.timestamp])
        return CausalSnapshot(logicalVersionID: context.id, recordParentVersionID: recordParent, deviceID: context.deviceID, deviceCounter: counter, changedFields: changed.sorted { $0.fieldName < $1.fieldName }, observedFieldVersions: observed.sorted { $0.fieldName < $1.fieldName })
    }

    private func latestVersion(field: String, id: String, db: Database) throws -> String? {
        try String.fetchOne(db, sql: "SELECT version_id FROM field_versions WHERE entity_type = ? AND entity_id = ? AND field_name = ? ORDER BY rowid DESC LIMIT 1", arguments: [spec.entity, id, field])
    }
}
