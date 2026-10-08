import Foundation
import TaisaStorage

public actor ConversationCoordinator {
    private struct PendingText: Sendable {
        let requestID: String
        let text: String
    }

    private let conversationID: String
    private let client: any ConversationClient
    private let voice: any ConversationVoiceControlling
    private var composer: ComposerState
    private var latestReply: ConversationReply?
    private var pendingText: PendingText?
    private var title: String?
    private var titleAuthority: TitleAuthority
    private var requestInFlight = false

    private init(
        conversationID: String,
        composer: ComposerState,
        client: any ConversationClient,
        voice: any ConversationVoiceControlling,
        title: String? = nil,
        titleAuthority: TitleAuthority = .localFallback,
        pendingText: (requestID: String, text: String)? = nil
    ) {
        self.conversationID = conversationID
        self.composer = composer
        self.client = client
        self.voice = voice
        self.title = title
        self.titleAuthority = titleAuthority
        self.pendingText = pendingText.map { PendingText(requestID: $0.requestID, text: $0.text) }
    }

    public static func new(
        conversationID: String,
        client: any ConversationClient,
        voice: any ConversationVoiceControlling
    ) -> ConversationCoordinator {
        ConversationCoordinator(conversationID: conversationID, composer: .waitingForReply, client: client, voice: voice)
    }

    public static func completed(
        conversationID: String,
        client: any ConversationClient,
        voice: any ConversationVoiceControlling,
        title: String? = nil,
        titleAuthority: TitleAuthority = .localFallback
    ) -> ConversationCoordinator {
        ConversationCoordinator(
            conversationID: conversationID, composer: .waitingForReply,
            client: client, voice: voice, title: title, titleAuthority: titleAuthority
        )
    }

    public static func restoredTextRequest(
        conversationID: String,
        requestID: String,
        text: String,
        client: any ConversationClient,
        voice: any ConversationVoiceControlling
    ) -> ConversationCoordinator {
        return ConversationCoordinator(
            conversationID: conversationID, composer: .failure(.retryable),
            client: client, voice: voice, pendingText: (requestID, text)
        )
    }

    public func snapshot() -> ConversationCoordinatorSnapshot {
        .init(
            conversationID: conversationID, composer: composer, latestReply: latestReply,
            title: title, titleAuthority: titleAuthority
        )
    }

    public func beginReply(mode: ConversationReplyMode) async throws {
        switch mode {
        case .voice:
            composer = .preparingVoice
            do {
                try await voice.beginReply()
                composer = .recording
            } catch {
                composer = .failure(.unavailable)
                throw error
            }
        case .text:
            composer = .typing("")
        }
    }

    public func switchToText() { composer = .typing("") }

    public func pauseVoice() async throws {
        try await voice.pauseReply()
        composer = .paused
    }

    public func resumeVoice() async throws {
        try await voice.resumeReply()
        composer = .recording
    }

    public func sendVoice() async throws {
        composer = .transcribing
        do {
            try await voice.sendReply()
            composer = .waitingForReply
        } catch {
            composer = .failure(.retryable)
            throw error
        }
    }

    public func send(_ input: ConversationInput) async throws {
        switch input {
        case .voice:
            try await beginReply(mode: .voice)
        case .text(let source):
            guard !requestInFlight else { throw ConversationFailure.busy }
            let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw ConversationFailure.invalidInput }
            let pending = PendingText(requestID: UUID().uuidString, text: text)
            pendingText = pending
            try await perform(pending)
        }
    }

    public func retry() async throws {
        if let pendingText {
            try await perform(pendingText)
        } else {
            try await voice.retry()
        }
    }

    public func saveDraft() async throws {
        if case .typing(let text) = composer {
            try await client.saveDraft(conversationID: conversationID, input: .text(text))
        } else {
            try await voice.saveDraft()
        }
    }

    public func discardDraft() async throws {
        try await client.discardDraft(conversationID: conversationID)
        try await voice.discardDraft()
        pendingText = nil
        composer = .waitingForReply
    }

    public func correctTranscript(messageID: String, text: String) async throws {
        composer = .coaching
        do {
            let reply = try await client.correctTranscript(
                conversationID: conversationID, messageID: messageID, text: text
            )
            accept(reply)
        } catch {
            composer = .failure(.retryable)
            throw error
        }
    }

    private func perform(_ pending: PendingText) async throws {
        guard !requestInFlight else { throw ConversationFailure.busy }
        requestInFlight = true
        defer { requestInFlight = false }
        composer = .coaching
        do {
            let reply = try await client.sendText(
                conversationID: conversationID, requestID: pending.requestID, text: pending.text
            )
            pendingText = nil
            accept(reply)
        } catch let failure as ConversationFailure {
            composer = .failure(failure)
            throw failure
        } catch {
            composer = .failure(.retryable)
            throw error
        }
    }

    private func accept(_ reply: ConversationReply) {
        latestReply = reply
        if titleAuthority != .user, let suggestion = reply.titleSuggestion {
            title = suggestion
            titleAuthority = .assistantSuggested
        }
        composer = .waitingForReply
    }
}
