import Foundation
import TaisaStorage
import TaisaVoice

public protocol ConversationClient: Sendable {
    func sendText(conversationID: String, requestID: String, text: String) async throws -> ConversationReply
    func saveDraft(conversationID: String, input: ConversationInput) async throws
    func discardDraft(conversationID: String) async throws
    func completeVoiceConversation(conversationID: String) async throws
    func correctTranscript(conversationID: String, requestID: String, messageID: String, text: String) async throws -> ConversationReply
}

public extension ConversationClient {
    func saveDraft(conversationID: String, input: ConversationInput) async throws {}
    func discardDraft(conversationID: String) async throws {}
    func correctTranscript(conversationID: String, requestID: String, messageID: String, text: String) async throws -> ConversationReply {
        throw ConversationFailure.unavailable
    }
}

public protocol ConversationVoiceControlling: Sendable {
    func beginReply() async throws
    func pauseReply() async throws
    func resumeReply() async throws
    func sendReply(onTranscriptAvailable: @escaping @Sendable () async -> Void) async throws
    func retry() async throws
    func saveDraft() async throws
    func discardDraft() async throws
}

public extension ConversationVoiceControlling {
    func pauseReply() async throws { throw ConversationFailure.unavailable }
    func resumeReply() async throws { throw ConversationFailure.unavailable }
    func sendReply(onTranscriptAvailable: @escaping @Sendable () async -> Void) async throws {
        throw ConversationFailure.unavailable
    }
    func retry() async throws {}
    func saveDraft() async throws {}
    func discardDraft() async throws {}
}

public struct VoiceSessionConversationAdapter: ConversationVoiceControlling {
    private let coordinator: VoiceSessionCoordinator
    private let makeTurn: @Sendable (String) -> VoiceTurnRecord

    public init(
        _ coordinator: VoiceSessionCoordinator,
        makeTurn: @escaping @Sendable (String) -> VoiceTurnRecord = { conversationID in
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            return VoiceTurnRecord(
                id: UUID().uuidString, conversationID: conversationID,
                transcriptionRequestID: UUID().uuidString,
                transcriptionIdempotencyKey: UUID().uuidString,
                coachingRequestID: UUID().uuidString,
                coachingIdempotencyKey: UUID().uuidString,
                state: .draft, stage: .capture, createdAtMS: now, updatedAtMS: now
            )
        }
    ) {
        self.coordinator = coordinator
        self.makeTurn = makeTurn
    }

    public func beginReply() async throws {
        let durable = await coordinator.snapshot().durable
        if durable.state.isTerminal || durable.state == .discarded {
            try await coordinator.send(.beginNextTurn(makeTurn(durable.conversationID)))
        }
        try await coordinator.send(.startRecording)
    }
    public func pauseReply() async throws { try await coordinator.send(.pauseRecording) }
    public func resumeReply() async throws { try await coordinator.send(.resumeRecording) }
    public func sendReply(onTranscriptAvailable: @escaping @Sendable () async -> Void) async throws {
        try await coordinator.sendRecordedAudio()
        await coordinator.waitForTranscriptOutcome()
        if await coordinator.snapshot().durable.acceptedTranscript != nil {
            await onTranscriptAvailable()
        }
        await coordinator.waitForIdle()
        try Self.requireCompleted(await coordinator.snapshot().durable.state)
    }
    static func requireCompleted(_ state: VoiceTurnState) throws {
        guard state == .completed else { throw ConversationFailure.retryable }
    }
    public func retry() async throws { try await coordinator.send(.retry) }
    public func saveDraft() async throws {
        let state = await coordinator.snapshot().durable.state
        if state == .recording { try await coordinator.send(.pauseRecording) }
    }
    public func discardDraft() async throws { try await coordinator.send(.discard) }
}
