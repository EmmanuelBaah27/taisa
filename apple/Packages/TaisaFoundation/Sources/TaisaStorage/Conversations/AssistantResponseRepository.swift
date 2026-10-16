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

    init(store: TaisaStore, failurePoint: AssistantResponseFailurePoint?) {
        self.store = store
        self.failurePoint = failurePoint
    }

    public func persist(_ write: AssistantResponseWrite) async throws {
        try Self.validate(write)
        do {
            try await store.write { db in
                try db.execute(
                    sql: "INSERT INTO messages (id, conversation_id, role, body, created_at_ms) VALUES (?, ?, ?, ?, ?)",
                    arguments: [write.message.id, write.message.conversationID, write.message.role, write.message.body, write.message.createdAtMS]
                )
                try failIfNeeded(.message)
                try Self.insertCompanions(write, db: db, after: failIfNeeded)
            }
        } catch let error as RepositoryError { throw error }
        catch { throw RepositoryError.persistenceFailed }
    }

    static func insertCompanions(
        _ write: AssistantResponseWrite,
        db: Database,
        after: (AssistantResponseFailurePoint) throws -> Void = { _ in }
    ) throws {
        let metadata = write.metadata
        try db.execute(sql: """
                    INSERT INTO assistant_response_metadata (
                        response_message_id, request_id, idempotency_receipt, mode, relevance,
                        context_sufficiency, stance, inference, confidence, approach, created_at_ms
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        metadata.responseMessageID, metadata.requestID, metadata.idempotencyReceipt,
                        metadata.mode.rawValue, metadata.relevance, metadata.contextSufficiency,
                        metadata.stance, metadata.inference, metadata.confidence, metadata.approach,
                        metadata.createdAtMS,
                    ])
        try after(.metadata)
        for source in write.sources.sorted(by: { $0.ordinal < $1.ordinal }) {
            try db.execute(sql: """
                        INSERT INTO assistant_response_sources (id, response_message_id, ordinal, source_id, source_type, excerpt)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """, arguments: [source.id, source.responseMessageID, source.ordinal, source.sourceID, source.sourceType, source.excerpt])
        }
        try after(.sources)
        if let proposal = write.proposal {
            try db.execute(sql: """
                        INSERT INTO assistant_proposals (
                            id, response_message_id, kind, canonical_payload, payload_digest, state,
                            target_type, target_id, target_version_id, decision_receipt, created_at_ms, resolved_at_ms
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """, arguments: [
                            proposal.id, proposal.responseMessageID, proposal.kind, proposal.canonicalPayload,
                            proposal.payloadDigest, proposal.state.rawValue, proposal.targetType, proposal.targetID,
                            proposal.targetVersionID, proposal.decisionReceipt, proposal.createdAtMS, proposal.resolvedAtMS,
                        ])
        }
        try after(.proposal)
    }

    public func upsertFeedback(_ feedback: ResponseFeedbackRecord) async throws {
        guard UUIDIdentity.canonical(feedback.responseMessageID) != nil,
              feedback.updatedAtMS >= 0,
              feedback.factors.count <= ResponseQualityFactor.allCases.count,
              feedback.detail == nil || (feedback.detail!.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 && feedback.detail!.count <= 4_000) else {
            throw RepositoryError.persistenceFailed
        }
        let factors = try JSONEncoder().encode(feedback.factors.map(\.rawValue))
        do {
            try await store.write { db in
                try db.execute(sql: """
                    INSERT INTO response_feedback (response_message_id, direction, factors_json, detail, updated_at_ms)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(response_message_id) DO UPDATE SET
                        direction = excluded.direction, factors_json = excluded.factors_json,
                        detail = excluded.detail, updated_at_ms = excluded.updated_at_ms
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
        resolvedAtMS: Int64
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
                try db.execute(sql: """
                    UPDATE assistant_proposals SET state = ?, target_type = ?, target_id = ?,
                        target_version_id = ?, decision_receipt = ?, resolved_at_ms = ?
                    WHERE id = ? COLLATE NOCASE AND state = 'pending'
                    """, arguments: [
                        state.rawValue, targetType, targetID, targetVersionID,
                        decisionReceipt, resolvedAtMS, id,
                    ])
                guard let updated = try Row.fetchOne(
                    db, sql: "SELECT * FROM assistant_proposals WHERE id = ? COLLATE NOCASE",
                    arguments: [id]
                ) else { throw RepositoryError.persistenceFailed }
                return Self.decodeProposal(updated)
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

    private static func decodeProposal(_ row: Row) -> AssistantProposalRecord {
        .init(id: row["id"], responseMessageID: row["response_message_id"], kind: row["kind"], canonicalPayload: row["canonical_payload"], payloadDigest: row["payload_digest"], state: AssistantProposalState(rawValue: row["state"])!, targetType: row["target_type"], targetID: row["target_id"], targetVersionID: row["target_version_id"], decisionReceipt: row["decision_receipt"], createdAtMS: row["created_at_ms"], resolvedAtMS: row["resolved_at_ms"])
    }

    private static func decodeFeedback(_ row: Row) throws -> ResponseFeedbackRecord {
        let raw = try JSONDecoder().decode([String].self, from: row["factors_json"] as Data)
        guard raw == raw.sorted(), Set(raw).count == raw.count,
              raw.allSatisfy({ ResponseQualityFactor(rawValue: $0) != nil }) else { throw RepositoryError.persistenceFailed }
        return .init(responseMessageID: row["response_message_id"], direction: ResponseFeedbackDirection(rawValue: row["direction"])!, factors: raw.compactMap(ResponseQualityFactor.init), detail: row["detail"], updatedAtMS: row["updated_at_ms"])
    }
}
