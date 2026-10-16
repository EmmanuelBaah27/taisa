import CryptoKit
import Foundation
import GRDB

enum AssistantResponseFailurePoint: String, CaseIterable, Sendable {
    case message, metadata, sources, proposal
}

public struct AssistantResponseRepository: Sendable {
    private let store: TaisaStore
    private let failurePoint: AssistantResponseFailurePoint?

    public init(store: TaisaStore) {
        self.store = store
        self.failurePoint = nil
    }

    public func persist(_ write: AssistantResponseWrite) async throws {
        try await persist(write, context: .init(id: UUID().uuidString, deviceID: UUID().uuidString, timestamp: write.message.createdAtMS))
    }

    init(store: TaisaStore, failurePoint: AssistantResponseFailurePoint?) {
        self.store = store
        self.failurePoint = failurePoint
    }

    public func persist(_ write: AssistantResponseWrite, context: MutationContext) async throws {
        try Self.validate(write)
        do {
            try await store.write { db in
                try Self.messageCore(store).create(write.message, context: Self.childContext(context, entity: "message", id: write.message.id), db: db)
                try failIfNeeded(.message)
                try Self.insertCompanions(write, context: context, store: store, db: db, after: failIfNeeded)
            }
        } catch let error as RepositoryError { throw error }
        catch { throw RepositoryError.persistenceFailed }
    }

    static func insertCompanions(
        _ write: AssistantResponseWrite,
        context: MutationContext,
        store: TaisaStore,
        db: Database,
        after: (AssistantResponseFailurePoint) throws -> Void = { _ in }
    ) throws {
        let metadata = write.metadata
        try metadataCore(store).create(metadata, context: childContext(context, entity: "assistant_response_metadata", id: metadata.id), db: db)
        try after(.metadata)
        for source in write.sources.sorted(by: { $0.ordinal < $1.ordinal }) {
            try sourceCore(store).create(source, context: childContext(context, entity: "assistant_response_source", id: source.id), db: db)
        }
        try after(.sources)
        if let proposal = write.proposal {
            try proposalCore(store).create(proposal, context: childContext(context, entity: "assistant_proposal", id: proposal.id), db: db)
        }
        try after(.proposal)
    }

    static func messageCore(_ store: TaisaStore) -> RepositoryCore<MessageRecord> {
        RepositoryCore(store: store, spec: .init(table: "messages", entity: "message", fields: [("id", "id"), ("conversationID", "conversation_id"), ("role", "role"), ("body", "body"), ("createdAtMS", "created_at_ms")], immutable: ["conversationID", "role", "body", "createdAtMS"], appendOnly: true))
    }

    static func metadataCore(_ store: TaisaStore) -> RepositoryCore<AssistantResponseMetadataRecord> {
        RepositoryCore(store: store, spec: .init(table: "assistant_response_metadata", entity: "assistant_response_metadata", identityColumn: "response_message_id", fields: [("responseMessageID", "response_message_id"), ("requestID", "request_id"), ("idempotencyReceipt", "idempotency_receipt"), ("mode", "mode"), ("relevance", "relevance"), ("contextSufficiency", "context_sufficiency"), ("stance", "stance"), ("inference", "inference"), ("confidence", "confidence"), ("approach", "approach"), ("createdAtMS", "created_at_ms")], immutable: ["responseMessageID", "requestID", "idempotencyReceipt", "mode", "relevance", "contextSufficiency", "stance", "inference", "confidence", "approach", "createdAtMS"], appendOnly: true))
    }

    static func sourceCore(_ store: TaisaStore) -> RepositoryCore<AssistantResponseSourceRecord> {
        RepositoryCore(store: store, spec: .init(table: "assistant_response_sources", entity: "assistant_response_source", opaqueIdentifierProperties: ["sourceID"], fields: [("id", "id"), ("responseMessageID", "response_message_id"), ("ordinal", "ordinal"), ("sourceID", "source_id"), ("sourceType", "source_type"), ("excerpt", "excerpt")], immutable: ["responseMessageID", "ordinal", "sourceID", "sourceType", "excerpt"], appendOnly: true))
    }

    static func proposalCore(_ store: TaisaStore) -> RepositoryCore<AssistantProposalRecord> {
        RepositoryCore(store: store, spec: .init(table: "assistant_proposals", entity: "assistant_proposal", fields: [("id", "id"), ("responseMessageID", "response_message_id"), ("kind", "kind"), ("canonicalPayload", "canonical_payload"), ("payloadDigest", "payload_digest"), ("state", "state"), ("targetType", "target_type"), ("targetID", "target_id"), ("targetVersionID", "target_version_id"), ("decisionReceipt", "decision_receipt"), ("createdAtMS", "created_at_ms"), ("resolvedAtMS", "resolved_at_ms")], immutable: ["responseMessageID", "kind", "canonicalPayload", "payloadDigest", "createdAtMS"], appendOnly: false))
    }

    static func childContext(_ context: MutationContext, entity: String, id: String) -> MutationContext {
        let digest = SHA256.hash(data: Data("\(context.id)|\(entity)|\(id)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let uuid = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        return .init(id: uuid.uuidString.lowercased(), deviceID: context.deviceID, timestamp: context.timestamp)
    }

    public func upsertFeedback(_ feedback: ResponseFeedbackRecord) async throws {
        guard UUIDIdentity.canonical(feedback.responseMessageID) != nil,
              feedback.updatedAtMS >= 0,
              feedback.factors.count <= ResponseQualityFactor.allCases.count,
              Set(feedback.factors).count == feedback.factors.count,
              feedback.detail == nil || (feedback.detail!.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 && feedback.detail!.count <= 4_000) else {
            throw RepositoryError.persistenceFailed
        }
        let factors = try JSONEncoder().encode(feedback.factors.sorted().map(\.rawValue))
        do {
            try await store.write { db in
                try db.execute(sql: """
                    INSERT INTO response_feedback (response_message_id, direction, factors_json, detail, updated_at_ms)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(response_message_id) DO UPDATE SET
                        direction = excluded.direction, factors_json = excluded.factors_json,
                        detail = excluded.detail, updated_at_ms = excluded.updated_at_ms
                    WHERE excluded.updated_at_ms > response_feedback.updated_at_ms
                    """, arguments: [feedback.responseMessageID, feedback.direction.rawValue, factors, feedback.detail, feedback.updatedAtMS])
            }
        } catch { throw RepositoryError.persistenceFailed }
    }

    public func removeFeedback(responseMessageID: String) async throws {
        guard let responseMessageID = UUIDIdentity.canonical(responseMessageID) else {
            throw RepositoryError.invalidIdentifier
        }
        do {
            try await store.write { db in
                try db.execute(
                    sql: "DELETE FROM response_feedback WHERE response_message_id = ? COLLATE NOCASE",
                    arguments: [responseMessageID]
                )
            }
        } catch { throw RepositoryError.persistenceFailed }
    }

    public func response(messageID: String) async throws -> AssistantResponseRecord? {
        guard let messageID = UUIDIdentity.canonical(messageID) else { throw RepositoryError.invalidIdentifier }
        do {
            return try await store.read { db in try Self.loadResponses(messageIDs: [messageID], db: db)[messageID] }
        } catch let error as RepositoryError { throw error }
        catch { throw RepositoryError.persistenceFailed }
    }

    public func proposal(id: String) async throws -> AssistantProposalRecord? {
        guard let id = UUIDIdentity.canonical(id) else { throw RepositoryError.invalidIdentifier }
        do {
            return try await store.read { db in
                try Row.fetchOne(
                    db, sql: "SELECT * FROM assistant_proposals WHERE id = ? COLLATE NOCASE",
                    arguments: [id]
                ).map(Self.decodeProposal)
            }
        } catch let error as RepositoryError { throw error }
        catch { throw RepositoryError.persistenceFailed }
    }

    public func resolveProposal(
        id: String,
        payloadDigest: String,
        state: AssistantProposalState,
        targetType: String?,
        targetID: String?,
        targetVersionID: String?,
        decisionReceipt: String,
        resolvedAtMS: Int64,
        context: MutationContext
    ) async throws -> AssistantProposalRecord {
        guard let id = UUIDIdentity.canonical(id), resolvedAtMS >= 0,
              state != .pending, !decisionReceipt.isEmpty else {
            throw RepositoryError.persistenceFailed
        }
        do {
            return try await store.write { db in
                guard let row = try Row.fetchOne(
                    db, sql: "SELECT * FROM assistant_proposals WHERE id = ? COLLATE NOCASE",
                    arguments: [id]
                ) else { throw RepositoryError.notFound }
                let current = Self.decodeProposal(row)
                if current.state != .pending {
                    guard current.payloadDigest == payloadDigest,
                          current.state == state,
                          current.targetType == targetType,
                          current.targetID == targetID,
                          current.targetVersionID == targetVersionID,
                          current.decisionReceipt == decisionReceipt else {
                        throw RepositoryError.mutationCollision
                    }
                    return current
                }
                guard current.payloadDigest == payloadDigest else {
                    throw RepositoryError.mutationCollision
                }
                let updated = AssistantProposalRecord(
                    id: current.id, responseMessageID: current.responseMessageID, kind: current.kind,
                    canonicalPayload: current.canonicalPayload, payloadDigest: current.payloadDigest,
                    state: state, targetType: targetType, targetID: targetID,
                    targetVersionID: targetVersionID, decisionReceipt: decisionReceipt,
                    createdAtMS: current.createdAtMS, resolvedAtMS: resolvedAtMS
                )
                try Self.proposalCore(store).update(
                    updated,
                    context: Self.childContext(context, entity: "assistant_proposal", id: id),
                    db: db
                )
                return updated
            }
        } catch let error as RepositoryError { throw error }
        catch { throw RepositoryError.persistenceFailed }
    }

    public func recentFeedback(limit: Int = 10) async throws -> [ResponseFeedbackRecord] {
        guard (1...10).contains(limit) else { throw RepositoryError.persistenceFailed }
        do {
            return try await store.read { db in
                try Row.fetchAll(db, sql: "SELECT * FROM response_feedback ORDER BY updated_at_ms DESC, response_message_id COLLATE NOCASE ASC LIMIT ?", arguments: [limit])
                    .map(Self.decodeFeedback)
            }
        } catch let error as RepositoryError { throw error }
        catch { throw RepositoryError.persistenceFailed }
    }

    public func replacePreferenceProfile(
        _ signals: [ResponsePreferenceSignalRecord], updatedAtMS: Int64
    ) async throws {
        guard signals.count <= 5, updatedAtMS >= 0,
              signals.allSatisfy({ $0.factor != .evidenceFidelity }),
              Set(signals.map(\.factor)).count == signals.count else {
            throw RepositoryError.persistenceFailed
        }
        let data = try JSONEncoder().encode(signals.sorted { $0.factor.rawValue < $1.factor.rawValue })
        do {
            try await store.write { db in
                try db.execute(sql: """
                    INSERT INTO preference_profiles (id, signals_json, enabled, updated_at_ms)
                    VALUES (1, ?, 1, ?)
                    ON CONFLICT(id) DO UPDATE SET signals_json = excluded.signals_json,
                        enabled = excluded.enabled, updated_at_ms = excluded.updated_at_ms
                    WHERE excluded.updated_at_ms >= preference_profiles.updated_at_ms
                    """, arguments: [data, updatedAtMS])
            }
        } catch { throw RepositoryError.persistenceFailed }
    }

    public func preferenceProfile() async throws -> [ResponsePreferenceSignalRecord] {
        do {
            return try await store.read { db in
                guard let row = try Row.fetchOne(db, sql: "SELECT signals_json, enabled FROM preference_profiles WHERE id = 1"),
                      (row["enabled"] as Int) == 1 else { return [] }
                let data: Data = row["signals_json"]
                let values = try JSONDecoder().decode([ResponsePreferenceSignalRecord].self, from: data)
                guard values.count <= 5, values.allSatisfy({ $0.factor != .evidenceFidelity }),
                      Set(values.map(\.factor)).count == values.count else {
                    throw RepositoryError.persistenceFailed
                }
                return values
            }
        } catch let error as RepositoryError { throw error }
        catch { throw RepositoryError.persistenceFailed }
    }

    public func resolveSources(
        in responses: [String: AssistantResponseRecord]
    ) async throws -> [String: AssistantResponseRecord] {
        do {
            return try await store.read { db in
                try responses.mapValues { response in
                    let sources = try response.sources.map { source in
                        AssistantResponseSourceRecord(
                            id: source.id, responseMessageID: source.responseMessageID,
                            ordinal: source.ordinal, sourceID: source.sourceID,
                            sourceType: source.sourceType,
                            excerpt: try Self.localSourceText(source, db: db)
                        )
                    }
                    return AssistantResponseRecord(metadata: response.metadata, sources: sources, proposal: response.proposal, feedback: response.feedback)
                }
            }
        } catch let error as RepositoryError { throw error }
        catch { throw RepositoryError.persistenceFailed }
    }

    private static func localSourceText(_ source: AssistantResponseSourceRecord, db: Database) throws -> String? {
        let table: String
        let column: String
        let entity: String
        switch source.sourceType {
        case "message": (table, column, entity) = ("messages", "body", "message")
        case "goal": (table, column, entity) = ("goals", "title", "goal")
        case "action": (table, column, entity) = ("actions", "title", "action")
        case "evidence": (table, column, entity) = ("evidence", "title", "evidence")
        case "memory": (table, column, entity) = ("memory_items", "content", "memory")
        case "insight": (table, column, entity) = ("insights", "body", "insight")
        default: return nil
        }
        return try String.fetchOne(db, sql: """
            SELECT \(column) FROM \(table)
            WHERE id = ? COLLATE NOCASE
              AND NOT EXISTS (
                SELECT 1 FROM tombstones
                WHERE entity_type = ? AND entity_id = ? COLLATE NOCASE
              )
            """, arguments: [source.sourceID, entity, source.sourceID])
    }

    static func loadResponses(messageIDs: [String], db: Database) throws -> [String: AssistantResponseRecord] {
        guard !messageIDs.isEmpty else { return [:] }
        let placeholders = Array(repeating: "?", count: messageIDs.count).joined(separator: ",")
        let arguments = StatementArguments(messageIDs)
        let metadata = try Row.fetchAll(db, sql: "SELECT * FROM assistant_response_metadata WHERE response_message_id IN (\(placeholders))", arguments: arguments)
        let sources = try Row.fetchAll(db, sql: "SELECT * FROM assistant_response_sources WHERE response_message_id IN (\(placeholders)) ORDER BY response_message_id, ordinal", arguments: arguments)
        let proposals = try Row.fetchAll(db, sql: "SELECT * FROM assistant_proposals WHERE response_message_id IN (\(placeholders))", arguments: arguments)
        let feedback = try Row.fetchAll(db, sql: "SELECT * FROM response_feedback WHERE response_message_id IN (\(placeholders))", arguments: arguments)
        let sourceMap = Dictionary(grouping: sources.map(decodeSource), by: \.responseMessageID)
        let proposalMap = Dictionary(uniqueKeysWithValues: proposals.map { let value = decodeProposal($0); return (value.responseMessageID, value) })
        let feedbackMap = Dictionary(uniqueKeysWithValues: try feedback.map { let value = try decodeFeedback($0); return (value.responseMessageID, value) })
        return Dictionary(uniqueKeysWithValues: metadata.map {
            let value = decodeMetadata($0)
            return (value.responseMessageID, AssistantResponseRecord(metadata: value, sources: sourceMap[value.responseMessageID] ?? [], proposal: proposalMap[value.responseMessageID], feedback: feedbackMap[value.responseMessageID]))
        })
    }

    private func failIfNeeded(_ point: AssistantResponseFailurePoint) throws {
        if failurePoint == point { throw RepositoryError.persistenceFailed }
    }

    static func validate(_ write: AssistantResponseWrite) throws {
        guard write.message.role == "assistant",
              UUIDIdentity.canonical(write.message.id) != nil,
              UUIDIdentity.canonical(write.message.conversationID) != nil,
              UUIDIdentity.canonical(write.metadata.responseMessageID) == write.message.id,
              UUIDIdentity.canonical(write.metadata.requestID) != nil,
              write.message.createdAtMS >= 0, write.metadata.createdAtMS >= 0,
              !write.message.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Set(write.sources.map(\.ordinal)).count == write.sources.count,
              write.sources.count <= 8,
              write.sources.allSatisfy({ UUIDIdentity.canonical($0.id) != nil && $0.responseMessageID == write.message.id && (0..<8).contains($0.ordinal) }),
              write.proposal.map({ UUIDIdentity.canonical($0.id) != nil && $0.responseMessageID == write.message.id }) ?? true else {
            throw RepositoryError.persistenceFailed
        }
    }

    private static func decodeMetadata(_ row: Row) -> AssistantResponseMetadataRecord {
        .init(responseMessageID: row["response_message_id"], requestID: row["request_id"], idempotencyReceipt: row["idempotency_receipt"], mode: AssistantResponseMode(rawValue: row["mode"])!, relevance: row["relevance"], contextSufficiency: row["context_sufficiency"], stance: row["stance"], inference: row["inference"], confidence: row["confidence"], approach: row["approach"], createdAtMS: row["created_at_ms"])
    }

    private static func decodeSource(_ row: Row) -> AssistantResponseSourceRecord {
        .init(id: row["id"], responseMessageID: row["response_message_id"], ordinal: row["ordinal"], sourceID: row["source_id"], sourceType: row["source_type"], excerpt: row["excerpt"])
    }

    static func decodeProposal(_ row: Row) -> AssistantProposalRecord {
        .init(id: row["id"], responseMessageID: row["response_message_id"], kind: row["kind"], canonicalPayload: row["canonical_payload"], payloadDigest: row["payload_digest"], state: AssistantProposalState(rawValue: row["state"])!, targetType: row["target_type"], targetID: row["target_id"], targetVersionID: row["target_version_id"], decisionReceipt: row["decision_receipt"], createdAtMS: row["created_at_ms"], resolvedAtMS: row["resolved_at_ms"])
    }

    private static func decodeFeedback(_ row: Row) throws -> ResponseFeedbackRecord {
        let raw = try JSONDecoder().decode([String].self, from: row["factors_json"] as Data)
        guard raw == raw.sorted(), Set(raw).count == raw.count,
              raw.allSatisfy({ ResponseQualityFactor(rawValue: $0) != nil }) else { throw RepositoryError.persistenceFailed }
        return .init(responseMessageID: row["response_message_id"], direction: ResponseFeedbackDirection(rawValue: row["direction"])!, factors: raw.compactMap(ResponseQualityFactor.init), detail: row["detail"], updatedAtMS: row["updated_at_ms"])
    }
}
