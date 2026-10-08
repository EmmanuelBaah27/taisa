import Foundation
import TaisaContracts
import TaisaStorage
import TaisaVoice

public actor GatewayConversationClient: ConversationClient {
    private let query: ConversationQuery
    private let repository: ConversationRepository
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
        let userMessageID = requestUUID.uuidString.lowercased()
        try await createMessageIfNeeded(.init(
            id: userMessageID, conversationID: conversationID,
            role: "user", body: normalized, createdAtMS: createdAt
        ))

        let response = try await requestCoaching(
            conversationID: conversationID, requestID: requestID,
            text: normalized, createdAtMS: createdAt
        )

        let assistantMessageID = derivedUUID(from: requestID, salt: 3)
        try await createMessageIfNeeded(.init(
            id: assistantMessageID, conversationID: conversationID,
            role: "assistant", body: response.reply, createdAtMS: max(createdAt, nowMS())
        ))
        try await completeConversation(
            id: conversationID,
            titleSuggestion: response.titleSuggestion,
            updatedAtMS: max(createdAt, nowMS())
        )
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

    public func correctTranscript(conversationID: String, messageID: String, text: String) async throws -> ConversationReply {
        let requestID = UUID().uuidString.lowercased()
        let snapshot = try await query.loadConversation(id: conversationID)
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
            text: normalized, createdAtMS: now
        )
        let corrected = MessageRecord(
            id: requestID, conversationID: conversationID,
            role: "user", body: normalized, createdAtMS: now
        )
        let regenerated = MessageRecord(
            id: derivedUUID(from: requestID, salt: 3), conversationID: conversationID,
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
        createdAtMS: Int64
    ) async throws -> CoachingResponse {
        let turn = VoiceTurnRecord(
            id: derivedUUID(from: requestID, salt: 1), conversationID: conversationID,
            transcriptionRequestID: derivedUUID(from: requestID, salt: 2),
            transcriptionIdempotencyKey: "text-no-transcription-\(requestID.lowercased())",
            coachingRequestID: requestID,
            coachingIdempotencyKey: "text-coaching-\(requestID.lowercased())",
            state: .coaching, stage: .coaching, acceptedTranscript: text,
            createdAtMS: createdAtMS, updatedAtMS: createdAtMS
        )
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

    private func createMessageIfNeeded(_ message: MessageRecord) async throws {
        guard try await repository.message(id: message.id) == nil else { return }
        try await repository.createMessage(message, context: context(message.createdAtMS))
    }

    private func completeConversation(id: String, titleSuggestion: String?, updatedAtMS: Int64) async throws {
        guard let current = try await repository.get(id: id) else { throw ConversationFailure.unavailable }
        let title = current.titleAuthority == .user ? current.title : (titleSuggestion ?? current.title)
        let authority: TitleAuthority = current.titleAuthority == .user ? .user : (titleSuggestion == nil ? current.titleAuthority : .assistantSuggested)
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
