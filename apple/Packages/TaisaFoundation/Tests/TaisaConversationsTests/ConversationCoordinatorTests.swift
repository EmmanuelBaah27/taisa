import Testing
import TaisaStorage
@testable import TaisaConversations

@Suite("Durable conversation coordinator")
struct ConversationCoordinatorTests {
    @Test func replyWaitsForExplicitIntent() async throws {
        let voice = VoiceIntentSpy()
        let coordinator = ConversationCoordinator.completed(
            conversationID: "00000000-0000-0000-0000-000000000001",
            client: ConversationClientSpy(), voice: voice
        )

        #expect(await coordinator.snapshot().composer == .waitingForReply)
        #expect(await voice.startCount == 0)
        try await coordinator.beginReply(mode: .voice)
        #expect(await voice.startCount == 1)
    }

    @Test func textSendUsesOneDurableRequestAcrossRetry() async throws {
        let client = ConversationClientSpy(failuresBeforeSuccess: 1)
        let coordinator = ConversationCoordinator.new(
            conversationID: "00000000-0000-0000-0000-000000000001",
            client: client, voice: VoiceIntentSpy()
        )

        await #expect(throws: ConversationFailure.self) {
            try await coordinator.send(.text("Prepare my review"))
        }
        try await coordinator.retry()

        let requestIDs = await client.requestIDs
        #expect(requestIDs.count == 2)
        #expect(Set(requestIDs).count == 1)
    }

    @Test func restoredTextRetryKeepsPersistedRequestIdentity() async throws {
        let client = ConversationClientSpy()
        let requestID = "00000000-0000-0000-0000-000000000009"
        let coordinator = ConversationCoordinator.restoredTextRequest(
            conversationID: "00000000-0000-0000-0000-000000000001",
            requestID: requestID, text: "Prepare my review",
            client: client, voice: VoiceIntentSpy()
        )

        try await coordinator.retry()
        #expect(await client.requestIDs == [requestID])
    }

    @Test func titleSuggestionNeverOverridesManualTitle() async throws {
        let client = ConversationClientSpy()
        let coordinator = ConversationCoordinator.completed(
            conversationID: "00000000-0000-0000-0000-000000000001",
            client: client, voice: VoiceIntentSpy(), title: "My title", titleAuthority: .user
        )

        try await coordinator.send(.text("Prepare my review"))
        let snapshot = await coordinator.snapshot()
        #expect(snapshot.title == "My title")
        #expect(snapshot.titleAuthority == .user)
    }

    @Test func firstSuggestionRefinesOnlyFallbackTitle() async throws {
        let coordinator = ConversationCoordinator.completed(
            conversationID: "00000000-0000-0000-0000-000000000001",
            client: ConversationClientSpy(), voice: VoiceIntentSpy(),
            title: "New conversation", titleAuthority: .localFallback
        )

        try await coordinator.send(.text("Prepare my review"))
        let snapshot = await coordinator.snapshot()
        #expect(snapshot.title == "Review preparation")
        #expect(snapshot.titleAuthority == .assistantSuggested)
    }

    @Test func rapidSendDoesNotStartSecondPaidRequest() async throws {
        let client = ConversationClientSpy(blocked: true)
        let coordinator = ConversationCoordinator.new(
            conversationID: "00000000-0000-0000-0000-000000000001",
            client: client, voice: VoiceIntentSpy()
        )
        let first = Task { try await coordinator.send(.text("First")) }
        while await client.requestIDs.isEmpty { await Task.yield() }

        await #expect(throws: ConversationFailure.busy) {
            try await coordinator.send(.text("Second"))
        }
        await client.release()
        try await first.value
        #expect(await client.requestIDs.count == 1)
    }
}

private actor VoiceIntentSpy: ConversationVoiceControlling {
    private(set) var startCount = 0
    func beginReply() async throws { startCount += 1 }
}

private actor ConversationClientSpy: ConversationClient {
    private var remainingFailures: Int
    private(set) var requestIDs: [String] = []
    private let blocked: Bool
    private var continuations: [CheckedContinuation<Void, Never>] = []

    init(failuresBeforeSuccess: Int = 0, blocked: Bool = false) {
        remainingFailures = failuresBeforeSuccess
        self.blocked = blocked
    }

    func sendText(conversationID: String, requestID: String, text: String) async throws -> ConversationReply {
        requestIDs.append(requestID)
        if blocked { await withCheckedContinuation { continuations.append($0) } }
        if remainingFailures > 0 {
            remainingFailures -= 1
            throw ConversationFailure.retryable
        }
        return ConversationReply(text: "Ready", titleSuggestion: "Review preparation")
    }

    func release() { continuations.forEach { $0.resume() }; continuations.removeAll() }
}
