import TaisaVoice

public protocol ConversationClient: Sendable {
    func sendText(conversationID: String, requestID: String, text: String) async throws -> ConversationReply
    func saveDraft(conversationID: String, input: ConversationInput) async throws
    func discardDraft(conversationID: String) async throws
    func correctTranscript(conversationID: String, messageID: String, text: String) async throws -> ConversationReply
}

public extension ConversationClient {
    func saveDraft(conversationID: String, input: ConversationInput) async throws {}
    func discardDraft(conversationID: String) async throws {}
    func correctTranscript(conversationID: String, messageID: String, text: String) async throws -> ConversationReply {
        throw ConversationFailure.unavailable
    }
}

public protocol ConversationVoiceControlling: Sendable {
    func beginReply() async throws
    func retry() async throws
    func saveDraft() async throws
    func discardDraft() async throws
}

public extension ConversationVoiceControlling {
    func retry() async throws {}
    func saveDraft() async throws {}
    func discardDraft() async throws {}
}

public struct VoiceSessionConversationAdapter: ConversationVoiceControlling {
    private let coordinator: VoiceSessionCoordinator

    public init(_ coordinator: VoiceSessionCoordinator) { self.coordinator = coordinator }

    public func beginReply() async throws { try await coordinator.send(.startRecording) }
    public func retry() async throws { try await coordinator.send(.retry) }
    public func saveDraft() async throws {
        let state = await coordinator.snapshot().durable.state
        if state == .recording { try await coordinator.send(.pauseRecording) }
    }
    public func discardDraft() async throws { try await coordinator.send(.discard) }
}
