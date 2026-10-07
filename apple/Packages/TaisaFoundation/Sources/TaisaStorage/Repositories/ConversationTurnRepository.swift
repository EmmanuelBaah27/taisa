import Foundation
import GRDB

public struct ConversationTurnRepository: Sendable {
    private let store: TaisaStore

    public init(store: TaisaStore) { self.store = store }

    public func turn(id: String) async throws -> VoiceTurnRecord? {
        guard let id = UUIDIdentity.canonical(id) else { throw RepositoryError.invalidIdentifier }
        do {
            return try await store.read { db in
                try Row.fetchOne(
                    db,
                    sql: "SELECT * FROM voice_turns WHERE id = ? COLLATE NOCASE",
                    arguments: [id]
                ).map(Self.decode)
            }
        } catch let error as RepositoryError { throw error }
        catch { throw RepositoryError.persistenceFailed }
    }

    public func latestResumableTurn(conversationID: String) async throws -> VoiceTurnRecord? {
        guard let conversationID = UUIDIdentity.canonical(conversationID) else {
            throw RepositoryError.invalidIdentifier
        }
        do {
            return try await store.read { db in
                try Row.fetchOne(
                    db,
                    sql: """
                        SELECT * FROM voice_turns
                        WHERE conversation_id = ? COLLATE NOCASE
                          AND stage NOT IN ('capture', 'finished')
                        ORDER BY updated_at_ms DESC, created_at_ms DESC, rowid DESC
                        LIMIT 1
                        """,
                    arguments: [conversationID]
                ).map(Self.decode)
            }
        } catch let error as RepositoryError { throw error }
        catch { throw RepositoryError.persistenceFailed }
    }

    public func checkpoint(
        _ source: VoiceTurnRecord,
        messages: [MessageRecord],
        cleanup: VoiceTurnCleanup?,
        context: MutationContext
    ) async throws {
        let turn = try Self.canonical(source)
        let context = try Self.canonical(context)
        try Self.validate(turn, messages: messages, cleanup: cleanup, context: context)
        do {
            try await store.write { db in
                let existing = try Row.fetchOne(
                    db, sql: "SELECT * FROM voice_turns WHERE id = ? COLLATE NOCASE",
                    arguments: [turn.id]
                ).map(Self.decode)
                if let existing {
                    try Self.validateTransition(from: existing, to: turn)
                }

                let persisted = cleanup?.completedAtMS == nil ? turn : Self.clearingAudio(turn)
                if let prior = try Row.fetchOne(
                    db,
                    sql: "SELECT entity_type, entity_id FROM outbox WHERE mutation_id = ? COLLATE NOCASE",
                    arguments: [context.id]
                ) {
                    guard (prior["entity_type"] as String) == "voice_turn",
                          UUIDIdentity.canonical(prior["entity_id"] as String) == turn.id,
                          existing == persisted,
                          try Self.messagesExistIdentically(messages, db: db),
                          try Self.cleanupMatches(cleanup, turnID: turn.id, db: db) else {
                        throw RepositoryError.mutationCollision
                    }
                    return
                }

                for message in messages {
                    try Self.insertMessage(message, deviceID: context.deviceID, timestamp: context.timestamp, db: db)
                }

                try Self.persist(persisted, exists: existing != nil, db: db)
                if let cleanup {
                    if let completedAtMS = cleanup.completedAtMS {
                        try db.execute(
                            sql: "DELETE FROM audio_cleanup_queue WHERE turn_id = ? COLLATE NOCASE",
                            arguments: [turn.id]
                        )
                        guard completedAtMS >= 0 else { throw RepositoryError.invalidTimestamp }
                    } else {
                        try db.execute(
                            sql: "INSERT INTO audio_cleanup_queue (turn_id, audio_file_id, completed_at_ms) VALUES (?, ?, NULL) ON CONFLICT(turn_id) DO UPDATE SET audio_file_id = excluded.audio_file_id, completed_at_ms = NULL",
                            arguments: [turn.id, cleanup.audioFileID]
                        )
                    }
                }
                try Self.insertTurnMutation(
                    persisted, operation: existing == nil ? "create" : "update",
                    context: context, db: db
                )
            }
        } catch let error as RepositoryError { throw error }
        catch { throw RepositoryError.persistenceFailed }
    }

    private static func messagesExistIdentically(_ messages: [MessageRecord], db: Database) throws -> Bool {
        for message in messages {
            guard let row = try Row.fetchOne(
                db, sql: "SELECT * FROM messages WHERE id = ? COLLATE NOCASE", arguments: [message.id]
            ), (row["conversation_id"] as String).lowercased() == message.conversationID.lowercased(),
               (row["role"] as String) == message.role,
               (row["body"] as String) == message.body,
               (row["created_at_ms"] as Int64) == message.createdAtMS else { return false }
        }
        return true
    }

    private static func cleanupMatches(
        _ cleanup: VoiceTurnCleanup?, turnID: String, db: Database
    ) throws -> Bool {
        let row = try Row.fetchOne(
            db, sql: "SELECT audio_file_id, completed_at_ms FROM audio_cleanup_queue WHERE turn_id = ? COLLATE NOCASE",
            arguments: [turnID]
        )
        guard let cleanup else { return row == nil }
        if cleanup.completedAtMS != nil { return row == nil }
        return row.map { ($0["audio_file_id"] as String) == cleanup.audioFileID } ?? false
    }

    private static func validate(
        _ turn: VoiceTurnRecord,
        messages: [MessageRecord],
        cleanup: VoiceTurnCleanup?,
        context: MutationContext
    ) throws {
        for id in [turn.id, turn.conversationID, turn.transcriptionRequestID,
                   turn.coachingRequestID, context.id, context.deviceID] {
            guard UUIDIdentity.canonical(id) != nil else { throw RepositoryError.invalidIdentifier }
        }
        guard !turn.transcriptionIdempotencyKey.isEmpty,
              !turn.coachingIdempotencyKey.isEmpty,
              turn.createdAtMS >= 0,
              turn.updatedAtMS >= turn.createdAtMS,
              context.timestamp >= 0,
              turn.retryCount >= 0,
              turn.audioDurationMS.map({ $0 >= 0 }) ?? true,
              turn.nextRetryAtMS.map({ $0 >= 0 }) ?? true,
              !(turn.acceptedTranscript != nil && turn.uncertainTranscript != nil) else {
            throw RepositoryError.persistenceFailed
        }
        guard Set(messages.map(\.id)).count == messages.count,
              messages.allSatisfy({ $0.conversationID == turn.conversationID }) else {
            throw RepositoryError.persistenceFailed
        }
        if let cleanup {
            guard !cleanup.audioFileID.isEmpty,
                  cleanup.completedAtMS.map({ $0 >= 0 }) ?? true else {
                throw RepositoryError.persistenceFailed
            }
        }
    }

    private static func validateTransition(from old: VoiceTurnRecord, to new: VoiceTurnRecord) throws {
        guard old.conversationID == new.conversationID,
              old.transcriptionRequestID == new.transcriptionRequestID,
              old.transcriptionIdempotencyKey == new.transcriptionIdempotencyKey,
              old.coachingRequestID == new.coachingRequestID,
              old.coachingIdempotencyKey == new.coachingIdempotencyKey,
              old.createdAtMS == new.createdAtMS else { throw RepositoryError.immutableRecord }
        guard !old.state.isTerminal || old.state == new.state else { throw RepositoryError.immutableRecord }
    }

    private static func persist(_ turn: VoiceTurnRecord, exists: Bool, db: Database) throws {
        let values: [DatabaseValueConvertible?] = [
            turn.id, turn.conversationID, turn.transcriptionRequestID,
            turn.transcriptionIdempotencyKey, turn.coachingRequestID,
            turn.coachingIdempotencyKey, turn.state.rawValue, turn.stage.rawValue,
            turn.audioFileID, turn.audioSHA256, turn.audioDurationMS,
            turn.acceptedTranscript, turn.uncertainTranscript, turn.retryCount,
            turn.nextRetryAtMS, turn.failureCode, turn.transcriptionReceipt,
            turn.coachingReceipt, turn.userMessageID, turn.assistantMessageID,
            turn.cleanupState.rawValue, turn.createdAtMS, turn.updatedAtMS,
        ]
        if exists {
            try db.execute(sql: """
                UPDATE voice_turns SET conversation_id = ?, transcription_request_id = ?,
                    transcription_idempotency_key = ?, coaching_request_id = ?,
                    coaching_idempotency_key = ?, state = ?, stage = ?, audio_file_id = ?,
                    audio_sha256 = ?, audio_duration_ms = ?, accepted_transcript = ?,
                    uncertain_transcript = ?, retry_count = ?, next_retry_at_ms = ?,
                    failure_code = ?, transcription_receipt = ?, coaching_receipt = ?,
                    user_message_id = ?, assistant_message_id = ?, cleanup_state = ?,
                    created_at_ms = ?, updated_at_ms = ? WHERE id = ? COLLATE NOCASE
                """, arguments: StatementArguments(Array(values.dropFirst()) + [turn.id.databaseValue]))
        } else {
            try db.execute(sql: """
                INSERT INTO voice_turns (
                    id, conversation_id, transcription_request_id, transcription_idempotency_key,
                    coaching_request_id, coaching_idempotency_key, state, stage, audio_file_id,
                    audio_sha256, audio_duration_ms, accepted_transcript, uncertain_transcript,
                    retry_count, next_retry_at_ms, failure_code, transcription_receipt,
                    coaching_receipt, user_message_id, assistant_message_id, cleanup_state,
                    created_at_ms, updated_at_ms
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: StatementArguments(values.map { $0?.databaseValue ?? .null }))
        }
        guard db.changesCount == 1 else { throw RepositoryError.persistenceFailed }
    }

    private static func insertMessage(
        _ raw: MessageRecord,
        deviceID: String,
        timestamp: Int64,
        db: Database
    ) throws {
        guard let id = UUIDIdentity.canonical(raw.id),
              let conversationID = UUIDIdentity.canonical(raw.conversationID),
              ["user", "assistant", "system"].contains(raw.role),
              raw.createdAtMS >= 0 else { throw RepositoryError.persistenceFailed }
        let message = MessageRecord(
            id: id, conversationID: conversationID, role: raw.role,
            body: raw.body, createdAtMS: raw.createdAtMS
        )
        try db.execute(
            sql: "INSERT INTO messages (id, conversation_id, role, body, created_at_ms) VALUES (?, ?, ?, ?, ?)",
            arguments: [message.id, message.conversationID, message.role, message.body, message.createdAtMS]
        )
        let mutation = MutationContext(id: message.id, deviceID: deviceID, timestamp: timestamp)
        try insertMutation(
            entity: "message", entityID: message.id, record: message,
            fields: ["conversationID", "role", "body", "createdAtMS"],
            context: mutation, operation: "create", db: db
        )
    }

    private static func insertTurnMutation(
        _ turn: VoiceTurnRecord,
        operation: String,
        context: MutationContext,
        db: Database
    ) throws {
        let projection = VoiceTurnSyncProjection(turn)
        try insertMutation(
            entity: "voice_turn", entityID: turn.id, record: projection,
            fields: VoiceTurnSyncProjection.fieldNames,
            context: context, operation: operation, db: db
        )
    }

    private static func insertMutation<Record: Encodable>(
        entity: String,
        entityID: String,
        record: Record,
        fields: [String],
        context: MutationContext,
        operation: String,
        db: Database
    ) throws {
        let previousCounter = try Int64.fetchOne(
            db, sql: "SELECT MAX(device_counter) FROM field_versions WHERE device_id = ? COLLATE NOCASE",
            arguments: [context.deviceID]
        ) ?? 0
        let counter = previousCounter + 1
        let parent = try String.fetchOne(
            db,
            sql: "SELECT version_id FROM field_versions WHERE entity_type = ? AND entity_id = ? COLLATE NOCASE AND field_name = '__record' ORDER BY rowid DESC LIMIT 1",
            arguments: [entity, entityID]
        )
        var versions: [FieldCausalVersion] = []
        for field in fields {
            let fieldParent = try String.fetchOne(
                db,
                sql: "SELECT version_id FROM field_versions WHERE entity_type = ? AND entity_id = ? COLLATE NOCASE AND field_name = ? ORDER BY rowid DESC LIMIT 1",
                arguments: [entity, entityID, field]
            )
            try db.execute(
                sql: "INSERT INTO field_versions (id, entity_type, entity_id, field_name, version_id, parent_version_id, device_id, device_counter, updated_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                arguments: [UUID().uuidString, entity, entityID, field, context.id, fieldParent, context.deviceID, counter, context.timestamp]
            )
            versions.append(FieldCausalVersion(
                fieldName: field, versionID: context.id,
                parentVersionID: fieldParent,
                ancestorVersionIDs: fieldParent.map { [$0] } ?? [],
                deviceCounter: counter
            ))
        }
        try db.execute(
            sql: "INSERT INTO field_versions (id, entity_type, entity_id, field_name, version_id, parent_version_id, device_id, device_counter, updated_at_ms) VALUES (?, ?, ?, '__record', ?, ?, ?, ?, ?)",
            arguments: [UUID().uuidString, entity, entityID, context.id, parent, context.deviceID, counter, context.timestamp]
        )
        let causality = CausalSnapshot(
            logicalVersionID: context.id, recordParentVersionID: parent,
            deviceID: context.deviceID, deviceCounter: counter,
            changedFields: versions, observedFieldVersions: []
        )
        try ChangeJournal.insert(
            db: db, context: context, entity: entity, entityID: entityID,
            operation: operation, record: record, causality: causality
        )
    }

    private static func clearingAudio(_ turn: VoiceTurnRecord) -> VoiceTurnRecord {
        VoiceTurnRecord(
            id: turn.id, conversationID: turn.conversationID,
            transcriptionRequestID: turn.transcriptionRequestID,
            transcriptionIdempotencyKey: turn.transcriptionIdempotencyKey,
            coachingRequestID: turn.coachingRequestID,
            coachingIdempotencyKey: turn.coachingIdempotencyKey,
            state: turn.state, stage: turn.stage,
            acceptedTranscript: turn.acceptedTranscript,
            uncertainTranscript: turn.uncertainTranscript,
            retryCount: turn.retryCount, nextRetryAtMS: turn.nextRetryAtMS,
            failureCode: turn.failureCode,
            transcriptionReceipt: turn.transcriptionReceipt,
            coachingReceipt: turn.coachingReceipt,
            userMessageID: turn.userMessageID,
            assistantMessageID: turn.assistantMessageID,
            cleanupState: .completed,
            createdAtMS: turn.createdAtMS, updatedAtMS: turn.updatedAtMS
        )
    }

    private static func canonical(_ record: VoiceTurnRecord) throws -> VoiceTurnRecord {
        guard let id = UUIDIdentity.canonical(record.id),
              let conversationID = UUIDIdentity.canonical(record.conversationID),
              let transcriptionRequestID = UUIDIdentity.canonical(record.transcriptionRequestID),
              let coachingRequestID = UUIDIdentity.canonical(record.coachingRequestID) else {
            throw RepositoryError.invalidIdentifier
        }
        return VoiceTurnRecord(
            id: id, conversationID: conversationID,
            transcriptionRequestID: transcriptionRequestID,
            transcriptionIdempotencyKey: record.transcriptionIdempotencyKey,
            coachingRequestID: coachingRequestID,
            coachingIdempotencyKey: record.coachingIdempotencyKey,
            state: record.state, stage: record.stage,
            audioFileID: record.audioFileID, audioSHA256: record.audioSHA256,
            audioDurationMS: record.audioDurationMS,
            acceptedTranscript: record.acceptedTranscript,
            uncertainTranscript: record.uncertainTranscript,
            retryCount: record.retryCount, nextRetryAtMS: record.nextRetryAtMS,
            failureCode: record.failureCode,
            transcriptionReceipt: record.transcriptionReceipt,
            coachingReceipt: record.coachingReceipt,
            userMessageID: record.userMessageID,
            assistantMessageID: record.assistantMessageID,
            cleanupState: record.cleanupState,
            createdAtMS: record.createdAtMS, updatedAtMS: record.updatedAtMS
        )
    }

    private static func canonical(_ context: MutationContext) throws -> MutationContext {
        guard let id = UUIDIdentity.canonical(context.id),
              let deviceID = UUIDIdentity.canonical(context.deviceID) else {
            throw RepositoryError.invalidIdentifier
        }
        return MutationContext(id: id, deviceID: deviceID, timestamp: context.timestamp)
    }

    private static func decode(_ row: Row) throws -> VoiceTurnRecord {
        guard let state = VoiceTurnState(rawValue: row["state"]),
              let stage = VoiceTurnStage(rawValue: row["stage"]),
              let cleanup = VoiceTurnCleanupState(rawValue: row["cleanup_state"]) else {
            throw RepositoryError.persistenceFailed
        }
        return VoiceTurnRecord(
            id: row["id"], conversationID: row["conversation_id"],
            transcriptionRequestID: row["transcription_request_id"],
            transcriptionIdempotencyKey: row["transcription_idempotency_key"],
            coachingRequestID: row["coaching_request_id"],
            coachingIdempotencyKey: row["coaching_idempotency_key"],
            state: state, stage: stage,
            audioFileID: row["audio_file_id"], audioSHA256: row["audio_sha256"],
            audioDurationMS: row["audio_duration_ms"],
            acceptedTranscript: row["accepted_transcript"],
            uncertainTranscript: row["uncertain_transcript"], retryCount: row["retry_count"],
            nextRetryAtMS: row["next_retry_at_ms"], failureCode: row["failure_code"],
            transcriptionReceipt: row["transcription_receipt"],
            coachingReceipt: row["coaching_receipt"], userMessageID: row["user_message_id"],
            assistantMessageID: row["assistant_message_id"], cleanupState: cleanup,
            createdAtMS: row["created_at_ms"], updatedAtMS: row["updated_at_ms"]
        )
    }
}

private struct VoiceTurnSyncProjection: Codable {
    static let fieldNames = [
        "conversationID", "transcriptionRequestID", "transcriptionIdempotencyKey",
        "coachingRequestID", "coachingIdempotencyKey", "state", "stage",
        "acceptedTranscript", "uncertainTranscript", "retryCount", "nextRetryAtMS",
        "failureCode", "transcriptionReceipt", "coachingReceipt", "userMessageID",
        "assistantMessageID", "cleanupState", "createdAtMS", "updatedAtMS",
    ]

    let id: String
    let conversationID: String
    let transcriptionRequestID: String
    let transcriptionIdempotencyKey: String
    let coachingRequestID: String
    let coachingIdempotencyKey: String
    let state: VoiceTurnState
    let stage: VoiceTurnStage
    let acceptedTranscript: String?
    let uncertainTranscript: String?
    let retryCount: Int
    let nextRetryAtMS: Int64?
    let failureCode: String?
    let transcriptionReceipt: String?
    let coachingReceipt: String?
    let userMessageID: String?
    let assistantMessageID: String?
    let cleanupState: VoiceTurnCleanupState
    let createdAtMS: Int64
    let updatedAtMS: Int64

    init(_ turn: VoiceTurnRecord) {
        id = turn.id; conversationID = turn.conversationID
        transcriptionRequestID = turn.transcriptionRequestID
        transcriptionIdempotencyKey = turn.transcriptionIdempotencyKey
        coachingRequestID = turn.coachingRequestID
        coachingIdempotencyKey = turn.coachingIdempotencyKey
        state = turn.state; stage = turn.stage
        acceptedTranscript = turn.acceptedTranscript
        uncertainTranscript = turn.uncertainTranscript
        retryCount = turn.retryCount; nextRetryAtMS = turn.nextRetryAtMS
        failureCode = turn.failureCode; transcriptionReceipt = turn.transcriptionReceipt
        coachingReceipt = turn.coachingReceipt; userMessageID = turn.userMessageID
        assistantMessageID = turn.assistantMessageID; cleanupState = turn.cleanupState
        createdAtMS = turn.createdAtMS; updatedAtMS = turn.updatedAtMS
    }
}
