import Foundation
import TaisaContracts
import TaisaStorage
import TaisaVoice

public actor GatewayConversationClient: ConversationClient {
    private let query: ConversationQuery
    private let repository: ConversationRepository
    private let turns: ConversationTurnRepository
    private let coaching: any VoiceCoachingRunning
    private let deviceID: String
    private let nowMS: @Sendable () -> Int64

    public init(
        store: TaisaStore,
        deviceID: UUID,
        coaching: any VoiceCoachingRunning,
        nowMS: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
    ) {
        query = ConversationQuery(store: store)
        repository = ConversationRepository(store: store)
        turns = ConversationTurnRepository(store: store)
        self.coaching = coaching
        self.deviceID = deviceID.uuidString.lowercased()
        self.nowMS = nowMS
    }

    public func sendText(conversationID: String, requestID: String, text: String) async throws -> ConversationReply {
        guard UUID(uuidString: conversationID) != nil, let requestUUID = UUID(uuidString: requestID) else {
            throw ConversationFailure.invalidInput
        }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw ConversationFailure.invalidInput }

        let createdAt = nowMS()
        try await repository.saveDraft(.init(
            id: derivedUUID(from: conversationID, salt: 4), conversationID: conversationID,
            inputMode: .text, text: normalized, voiceTurnID: nil,
            recoveryKind: .retryableCoaching, createdAtMS: createdAt, updatedAtMS: createdAt
        ))
        let userMessageID = requestUUID.uuidString.lowercased()
        try await createMessageIfNeeded(.init(
            id: userMessageID, conversationID: conversationID,
            role: "user", body: normalized, createdAtMS: createdAt
        ))

        let response = try await requestCoaching(
            conversationID: conversationID, requestID: requestID,
            text: normalized, createdAtMS: createdAt,
            userMessageID: userMessageID, assistantMessageID: nil, failureCode: "pending_text"
        )

        let assistantMessageID = derivedUUID(from: requestID, salt: 3)
        try await createMessageIfNeeded(.init(
            id: assistantMessageID, conversationID: conversationID,
            role: "assistant", body: response.reply, createdAtMS: max(createdAt, nowMS())
        ))
        try await finishTurn(
            conversationID: conversationID, requestID: requestID, text: normalized,
            createdAtMS: createdAt, userMessageID: userMessageID,
            assistantMessageID: assistantMessageID
        )
        try await completeConversation(
            id: conversationID,
            titleSuggestion: response.titleSuggestion,
            updatedAtMS: max(createdAt, nowMS())
        )
        try await discardDrafts(conversationID: conversationID)
        return ConversationReply(text: response.reply, titleSuggestion: response.titleSuggestion)
    }

    public func saveDraft(conversationID: String, input: ConversationInput) async throws {
        guard case .text(let text) = input else { return }
        let now = nowMS()
        try await repository.saveDraft(.init(
            id: derivedUUID(from: conversationID, salt: 4), conversationID: conversationID,
            inputMode: .text, text: text, voiceTurnID: nil, recoveryKind: .saved,
            createdAtMS: now, updatedAtMS: now
        ))
    }

    public func discardDraft(conversationID: String) async throws {
        let snapshot = try await query.loadConversation(id: conversationID)
        for draft in snapshot.drafts { try await repository.discardDraft(id: draft.id) }
    }

    public func completeVoiceConversation(conversationID: String) async throws {
        try await completeConversation(
            id: conversationID,
            titleSuggestion: nil,
            updatedAtMS: nowMS()
        )
    }

    public func correctTranscript(conversationID: String, requestID: String, messageID: String, text: String) async throws -> ConversationReply {
        guard UUID(uuidString: requestID) != nil else { throw ConversationFailure.invalidInput }
        let snapshot = try await query.loadConversation(id: conversationID)
        let regeneratedID = derivedUUID(from: requestID, salt: 3)
        if snapshot.revisions.contains(where: {
            $0.messageID == messageID && $0.replacementMessageID == requestID.lowercased()
        }), let regenerated = snapshot.visibleMessages.first(where: { $0.id == regeneratedID }) {
            try await finishTurn(
                conversationID: conversationID, requestID: requestID, text: text,
                createdAtMS: nowMS(), userMessageID: requestID,
                assistantMessageID: regeneratedID
            )
            return ConversationReply(text: regenerated.body, titleSuggestion: nil)
        }
        guard let originalIndex = snapshot.visibleMessages.firstIndex(where: { $0.id == messageID }),
              snapshot.visibleMessages.indices.contains(originalIndex + 1),
              snapshot.visibleMessages[originalIndex + 1].role == "assistant" else {
            throw ConversationFailure.unavailable
        }
        let now = nowMS()
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw ConversationFailure.invalidInput }
        let response = try await requestCoaching(
            conversationID: conversationID, requestID: requestID,
            text: normalized, createdAtMS: now,
            userMessageID: messageID,
            assistantMessageID: snapshot.visibleMessages[originalIndex + 1].id,
            failureCode: "pending_correction"
        )
        let corrected = MessageRecord(
            id: requestID, conversationID: conversationID,
            role: "user", body: normalized, createdAtMS: now
        )
        let regenerated = MessageRecord(
            id: regeneratedID, conversationID: conversationID,
            role: "assistant", body: response.reply, createdAtMS: max(now, nowMS())
        )
        try await repository.applyCorrection(.init(
            revisionID: UUID().uuidString,
            originalUserMessageID: messageID,
            originalAssistantMessageID: snapshot.visibleMessages[originalIndex + 1].id,
            correctedUserMessage: corrected,
            regeneratedAssistantMessage: regenerated,
            createdAtMS: now
        ), context: context(now))
        try await finishTurn(
            conversationID: conversationID, requestID: requestID, text: normalized,
            createdAtMS: now, userMessageID: corrected.id,
            assistantMessageID: regenerated.id
        )
        try await completeConversation(
            id: conversationID,
            titleSuggestion: nil,
            updatedAtMS: max(now, nowMS())
        )
        return ConversationReply(text: response.reply, titleSuggestion: nil)
    }

    private func requestCoaching(
        conversationID: String,
        requestID: String,
        text: String,
        createdAtMS: Int64,
        userMessageID: String?,
        assistantMessageID: String?,
        failureCode: String?
    ) async throws -> CoachingResponse {
        let turnID = derivedUUID(from: requestID, salt: 1)
        let persisted = try await turns.turn(id: turnID)
        let durableCreatedAt = persisted?.createdAtMS ?? createdAtMS
        let turn = VoiceTurnRecord(
            id: turnID, conversationID: conversationID,
            transcriptionRequestID: derivedUUID(from: requestID, salt: 2),
            transcriptionIdempotencyKey: "text-no-transcription-\(requestID.lowercased())",
            coachingRequestID: requestID,
            coachingIdempotencyKey: "text-coaching-\(requestID.lowercased())",
            state: .coaching, stage: .coaching, acceptedTranscript: text,
            failureCode: failureCode, userMessageID: userMessageID,
            assistantMessageID: assistantMessageID,
            createdAtMS: durableCreatedAt, updatedAtMS: max(durableCreatedAt, nowMS())
        )
        try await turns.checkpoint(turn, messages: [], cleanup: nil, context: context(nowMS()))
        let stream = try await coaching.stream(for: turn)
        var completion: CoachingResponse?
        for try await event in stream {
            switch event {
            case .delta: continue
            case .completed(_, _, let response, _): completion = response
            case .failed(_, _, _, let retryable):
                throw retryable ? ConversationFailure.retryable : ConversationFailure.unavailable
            }
        }
        guard let completion else { throw ConversationFailure.retryable }
        return completion
    }

    private func finishTurn(
        conversationID: String, requestID: String, text: String, createdAtMS: Int64,
        userMessageID: String, assistantMessageID: String
    ) async throws {
        let completedAt = max(createdAtMS, nowMS())
        let turnID = derivedUUID(from: requestID, salt: 1)
        let durableCreatedAt = try await turns.turn(id: turnID)?.createdAtMS ?? createdAtMS
        let turn = VoiceTurnRecord(
            id: turnID, conversationID: conversationID,
            transcriptionRequestID: derivedUUID(from: requestID, salt: 2),
            transcriptionIdempotencyKey: "text-no-transcription-\(requestID.lowercased())",
            coachingRequestID: requestID,
            coachingIdempotencyKey: "text-coaching-\(requestID.lowercased())",
            state: .completed, stage: .finished, acceptedTranscript: text,
            transcriptionReceipt: "not-required", coachingReceipt: requestID.lowercased(),
            userMessageID: userMessageID, assistantMessageID: assistantMessageID,
            cleanupState: .completed, createdAtMS: durableCreatedAt,
            updatedAtMS: max(durableCreatedAt, completedAt)
        )
        try await turns.checkpoint(turn, messages: [], cleanup: nil, context: context(completedAt))
    }

    private func createMessageIfNeeded(_ message: MessageRecord) async throws {
        guard try await repository.message(id: message.id) == nil else { return }
        try await repository.createMessage(message, context: context(message.createdAtMS))
    }

    private func discardDrafts(conversationID: String) async throws {
        let snapshot = try await query.loadConversation(id: conversationID)
        for draft in snapshot.drafts { try await repository.discardDraft(id: draft.id) }
    }

    private func completeConversation(id: String, titleSuggestion: String?, updatedAtMS: Int64) async throws {
        guard let current = try await repository.get(id: id) else { throw ConversationFailure.unavailable }
        let maySuggest = current.titleAuthority == .localFallback
        let title = maySuggest ? (titleSuggestion ?? current.title) : current.title
        let authority: TitleAuthority = maySuggest && titleSuggestion != nil ? .assistantSuggested : current.titleAuthority
        try await repository.update(.init(
            id: current.id, title: title, lifecycle: .completed,
            titleAuthority: authority, createdAtMS: current.createdAtMS,
            updatedAtMS: updatedAtMS
        ), context: context(updatedAtMS))
    }

    private func context(_ timestamp: Int64) -> MutationContext {
        MutationContext(id: UUID().uuidString, deviceID: deviceID, timestamp: timestamp)
    }

    private func derivedUUID(from source: String, salt: UInt8) -> String {
        guard var uuid = UUID(uuidString: source)?.uuid else { return UUID().uuidString.lowercased() }
        uuid.15 ^= salt
        return UUID(uuid: uuid).uuidString.lowercased()
    }
}
