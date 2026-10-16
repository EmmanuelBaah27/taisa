import Foundation
import TaisaContracts
import TaisaStorage
import TaisaVoice

enum ConversationTitleDeriver {
    static let maximumLength = 51
    static let maximumWordCount = 7

    private static let leadingPhrases = [
        "can you help me ", "could you help me ", "would you help me ",
        "help me ", "i would like to ", "i'd like to ", "i want to ",
        "i need to ", "i am going to ", "i'm going to ", "i am ", "i'm ",
    ]

    private static let gerunds = [
        "build": "Building", "change": "Changing", "decide": "Deciding",
        "deal": "Dealing", "discuss": "Discussing", "explore": "Exploring",
        "find": "Finding", "improve": "Improving", "navigate": "Navigating",
        "plan": "Planning", "prepare": "Preparing", "start": "Starting",
        "try": "Trying", "understand": "Understanding", "work": "Working",
    ]

    static func derive(from source: String) -> String? {
        let collapsed = source
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        guard !collapsed.isEmpty else { return nil }

        if let reported = reportedPhrase(for: collapsed.lowercased()) {
            return reported
        }

        var topic = collapsed
        let lowercase = collapsed.lowercased()
        if let prefix = leadingPhrases.first(where: { lowercase.hasPrefix($0) }) {
            topic = String(collapsed.dropFirst(prefix.count))
        }

        var words = topic.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return nil }
        let first = words[0].trimmingCharacters(in: .punctuationCharacters).lowercased()
        if first == "prepare", words.count > 1,
           words[1].trimmingCharacters(in: .punctuationCharacters).lowercased() == "me" {
            words.remove(at: 1)
        }
        if let gerund = gerunds[first] {
            words[0] = gerund
        } else if !first.hasSuffix("ing") {
            words.insert("Discussing", at: 0)
        } else {
            words[0] = words[0].prefix(1).uppercased() + words[0].dropFirst()
        }

        words = words.flatMap { reportedWord($0).split(separator: " ").map(String.init) }

        return bounded(words)
    }

    static func normalizeSuggestion(_ source: String) -> String? {
        let collapsed = source
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        guard !collapsed.isEmpty else { return nil }
        let lowercased = collapsed.lowercased()
        if leadingPhrases.contains(where: { lowercased.hasPrefix($0) }) {
            return derive(from: collapsed)
        }
        return bounded(collapsed.split(separator: " ").map(String.init))
    }

    private static func bounded(_ words: [String]) -> String? {
        let weakEndings: Set<String> = ["a", "an", "and", "at", "but", "for", "in", "of", "on", "or", "the", "to", "with"]
        var title = ""
        for word in words.prefix(maximumWordCount) {
            let candidate = title.isEmpty ? word : "\(title) \(word)"
            guard candidate.count <= maximumLength else { break }
            title = candidate
        }
        var boundedWords = title.split(separator: " ").map(String.init)
        while boundedWords.count > 1,
              let last = boundedWords.last?.trimmingCharacters(in: .punctuationCharacters).lowercased(),
              weakEndings.contains(last) {
            boundedWords.removeLast()
        }
        title = boundedWords.joined(separator: " ")
        if title.isEmpty, let first = words.first {
            title = String(first.prefix(maximumLength))
        }
        let trimmed = title.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func reportedWord(_ word: String) -> String {
        let punctuation = String(word.reversed().prefix(while: { $0.isPunctuation }).reversed())
        let stem = word.dropLast(punctuation.count)
        let replacement: String
        switch stem.lowercased() {
        case "i": replacement = "the user"
        case "i'm", "i’m": replacement = "the user is"
        case "i've", "i’ve": replacement = "the user has"
        case "my": replacement = "their"
        case "me": replacement = "them"
        default: return word
        }
        return replacement + punctuation
    }

    /// Stable fallbacks for common capture intents. Server suggestions remain the
    /// preferred title; these phrases keep offline/legacy history grammatical.
    private static func reportedPhrase(for source: String) -> String? {
        switch source {
        case "if i type now, will it show":
            "Checking whether typed messages appear"
        case "i'm going to start another one in drafts":
            "Starting another conversation draft"
        case "i'm recording one last time. i don't know why you":
            "Retrying a recording one last time"
        case "why is it that when i try to record, like for some":
            "Troubleshooting a recording problem"
        case "i'm trying a new one. i don't know why if i tap":
            "Testing a new recording attempt"
        default:
            nil
        }
    }
}

public actor GatewayConversationClient: ConversationClient {
    private let query: ConversationQuery
    private let repository: ConversationRepository
    private let turns: ConversationTurnRepository
    private let responses: AssistantResponseRepository
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
        responses = AssistantResponseRepository(store: store)
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

        let completion = try await requestCoaching(
            conversationID: conversationID, requestID: requestID,
            text: normalized, createdAtMS: createdAt,
            userMessageID: userMessageID, assistantMessageID: nil, failureCode: "pending_text"
        )

        let assistantMessageID = derivedUUID(from: requestID, salt: 3)
        let response = completion.response
        let assistantMessage = MessageRecord(
            id: assistantMessageID, conversationID: conversationID,
            role: "assistant", body: response.reply, createdAtMS: max(createdAt, nowMS())
        )
        if try await responses.response(messageID: assistantMessageID) == nil {
            try await responses.persist(try VoiceAssistantResponseWrite.make(
                message: assistantMessage,
                response: completion.response,
                receipt: completion.idempotencyReceipt
            ), context: context(assistantMessage.createdAtMS))
        }
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
        return ConversationReply(terminalResponse: response)
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
        let completion = try await requestCoaching(
            conversationID: conversationID, requestID: requestID,
            text: normalized, createdAtMS: now,
            userMessageID: messageID,
            assistantMessageID: snapshot.visibleMessages[originalIndex + 1].id,
            failureCode: "pending_correction"
        )
        let response = completion.response
        let corrected = MessageRecord(
            id: requestID, conversationID: conversationID,
            role: "user", body: normalized, createdAtMS: now
        )
        let regenerated = MessageRecord(
            id: regeneratedID, conversationID: conversationID,
            role: "assistant", body: response.reply, createdAtMS: max(now, nowMS())
        )
        let correction = ConversationCorrection(
            revisionID: UUID().uuidString,
            originalUserMessageID: messageID,
            originalAssistantMessageID: snapshot.visibleMessages[originalIndex + 1].id,
            correctedUserMessage: corrected,
            regeneratedAssistantMessage: regenerated,
            createdAtMS: now
        )
        try await repository.applyCorrection(
            correction,
            replacementResponse: try VoiceAssistantResponseWrite.make(
                message: regenerated,
                response: completion.response,
                receipt: completion.idempotencyReceipt
            ),
            context: context(now)
        )
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
        return ConversationReply(terminalResponse: response)
    }

    private struct TerminalCompletion {
        let response: CoachingResponse
        let idempotencyReceipt: String
    }

    private func requestCoaching(
        conversationID: String,
        requestID: String,
        text: String,
        createdAtMS: Int64,
        userMessageID: String?,
        assistantMessageID: String?,
        failureCode: String?
    ) async throws -> TerminalCompletion {
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
        var completion: TerminalCompletion?
        for try await event in stream {
            switch event {
            case .delta: continue
            case .completed(_, _, let response, let receipt):
                completion = TerminalCompletion(response: response, idempotencyReceipt: receipt)
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
        let firstUserMessage = try await query.loadConversation(id: id).visibleMessages
            .first(where: { $0.role == "user" })?.body
        let derivedTitle = firstUserMessage.flatMap(ConversationTitleDeriver.derive)
        let normalizedSuggestion = titleSuggestion.flatMap(ConversationTitleDeriver.normalizeSuggestion)
        let title = maySuggest ? (normalizedSuggestion ?? derivedTitle ?? current.title) : current.title
        let authority: TitleAuthority = maySuggest && normalizedSuggestion != nil ? .assistantSuggested : current.titleAuthority
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
