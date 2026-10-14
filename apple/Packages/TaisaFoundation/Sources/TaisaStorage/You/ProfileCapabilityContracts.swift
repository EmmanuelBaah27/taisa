import Foundation
import GRDB

public enum CapabilityID: String, Codable, Sendable, CaseIterable {
    case voice
    case seniorSelf = "senior-self"
    case insights
}

public enum CapabilityGovernanceState: String, Codable, Sendable, CaseIterable {
    case learning, ready, trial, trusted
}

public enum CapabilityDecisionSource: String, Codable, Sendable {
    case user
}

public enum CapabilityTransportSource: String, Codable, Sendable {
    case direct, `import`, restore
}

public struct CapabilityStateRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: CapabilityID { capability }
    public let capability: CapabilityID
    public let state: CapabilityGovernanceState
    public let decisionSource: CapabilityDecisionSource
    public let transportSource: CapabilityTransportSource
    public let decidedAtMS: Int64
    public let updatedAtMS: Int64
}

public enum YouContractError: Error, Sendable, Equatable, CaseIterable {
    case promotionEvidenceRequired
    case staleDecision
    case decisionCollision
    case invalidProfile
    case persistenceFailed
}

public struct CapabilityCommandRepository: Sendable {
    private let store: TaisaStore

    public init(store: TaisaStore) { self.store = store }

    public func get(_ capability: CapabilityID) async throws -> CapabilityStateRecord? {
        do {
            return try await store.read { db in
                try Self.fetch(capability, from: db)
            }
        } catch let error as YouContractError {
            throw error
        } catch {
            throw YouContractError.persistenceFailed
        }
    }

    public func list() async throws -> [CapabilityStateRecord] {
        do {
            return try await store.read { db in
                try CapabilityID.allCases.compactMap { try Self.fetch($0, from: db) }
            }
        } catch let error as YouContractError {
            throw error
        } catch {
            throw YouContractError.persistenceFailed
        }
    }

    @discardableResult
    public func set(
        _ capability: CapabilityID,
        to state: CapabilityGovernanceState,
        evidence: String?,
        context: MutationContext
    ) async throws -> CapabilityStateRecord {
        guard context.timestamp >= 0 else { throw YouContractError.persistenceFailed }
        if state != .learning && (evidence?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false) {
            throw YouContractError.promotionEvidenceRequired
        }
        do {
            return try await store.write { db in
                if let existing = try Self.fetch(capability, from: db) {
                    guard context.timestamp >= existing.updatedAtMS else { throw YouContractError.staleDecision }
                    if context.timestamp == existing.updatedAtMS {
                        guard state == existing.state else { throw YouContractError.decisionCollision }
                        return existing
                    }
                    try db.execute(
                        sql: "UPDATE capability_states SET state = ?, decision_source = 'user', transport_source = 'direct', decided_at_ms = ?, updated_at_ms = ? WHERE capability_id = ?",
                        arguments: [state.rawValue, context.timestamp, context.timestamp, capability.rawValue]
                    )
                } else {
                    try db.execute(
                        sql: "INSERT INTO capability_states (capability_id, state, decision_source, transport_source, decided_at_ms, updated_at_ms) VALUES (?, ?, 'user', 'direct', ?, ?)",
                        arguments: [capability.rawValue, state.rawValue, context.timestamp, context.timestamp]
                    )
                }
                guard let saved = try Self.fetch(capability, from: db) else { throw YouContractError.persistenceFailed }
                return saved
            }
        } catch let error as YouContractError {
            throw error
        } catch {
            throw YouContractError.persistenceFailed
        }
    }

    private static func fetch(_ capability: CapabilityID, from db: Database) throws -> CapabilityStateRecord? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM capability_states WHERE capability_id = ?", arguments: [capability.rawValue]) else { return nil }
        guard let state = CapabilityGovernanceState(rawValue: row["state"]),
              let decisionSource = CapabilityDecisionSource(rawValue: row["decision_source"]),
              let transportSource = CapabilityTransportSource(rawValue: row["transport_source"])
        else { throw YouContractError.persistenceFailed }
        return CapabilityStateRecord(
            capability: capability,
            state: state,
            decisionSource: decisionSource,
            transportSource: transportSource,
            decidedAtMS: row["decided_at_ms"],
            updatedAtMS: row["updated_at_ms"]
        )
    }
}

public struct ProfileCommandRepository: Sendable {
    private let repository: ProfileRepository

    public init(store: TaisaStore) { repository = ProfileRepository(store: store) }

    public func get(id: String) async throws -> ProfileRecord? { try await repository.get(id: id) }

    @discardableResult
    public func save(
        id: String,
        displayName: String,
        headline: String,
        biography: String,
        context: MutationContext
    ) async throws -> ProfileRecord {
        let fields = [displayName, headline, biography].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard fields[0].count <= 80, fields[1].count <= 160, fields[2].count <= 2_000,
              fields.allSatisfy({ !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) })
        else { throw YouContractError.invalidProfile }
        let record = ProfileRecord(
            id: id,
            displayName: fields[0],
            headline: fields[1],
            biography: fields[2],
            updatedAtMS: context.timestamp
        )
        do {
            if try await repository.get(id: id) == nil {
                try await repository.create(record, context: context)
            } else {
                try await repository.update(record, context: context)
            }
            return record
        } catch let error as YouContractError {
            throw error
        } catch {
            throw YouContractError.persistenceFailed
        }
    }
}
