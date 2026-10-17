import Foundation
import Testing
import TaisaContracts
import TaisaStorage
import TaisaVoice
@testable import TaisaConversations

private actor GatewayConversationTestKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}

private actor UnusedCoachingRunner: VoiceCoachingRunning {
    func stream(for turn: VoiceTurnRecord) async throws -> AsyncThrowingStream<CoachingStreamEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private actor CompletedCoachingRunner: VoiceCoachingRunning {
    func stream(for turn: VoiceTurnRecord) async throws -> AsyncThrowingStream<CoachingStreamEvent, Error> {
        let data = Data(#"{"type":"coaching.completed","requestId":"\#(turn.coachingRequestID)","sequence":0,"response":{"requestId":"\#(turn.coachingRequestID)","reply":"Grounded reply","mode":"coach","relevance":"career-relevant","contextSufficiency":"sufficient","stance":"nudge","explanation":{"mode":"nudge","evidence":[],"inference":"A bounded inference","confidence":"medium","approach":"Offer one step"},"proposal":null,"usage":{"provider":"anthropic","model":"fixture","estimatedCostUsd":0},"titleSuggestion":null},"idempotencyReceipt":"receipt-1"}"#.utf8)
        let event = try JSONDecoder().decode(CoachingStreamEvent.self, from: data)
        return AsyncThrowingStream { continuation in continuation.yield(event); continuation.finish() }
    }
}

@Suite(.serialized)
struct GatewayConversationClientTests {
    @Test func validTerminalPersistsAssistantMessageAndCompanionsAtomically() async throws {
        let fixture = try await gatewayFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let requestID = "00000000-0000-4000-8000-000000000921"
        let reply = try await GatewayConversationClient(store: fixture.store, deviceID: fixture.deviceID, coaching: CompletedCoachingRunner(), nowMS: { 2 })
            .sendText(conversationID: fixture.conversationID, requestID: requestID, text: "Help me prepare")
        let snapshot = try await ConversationQuery(store: fixture.store).loadConversation(id: fixture.conversationID)
        #expect(reply.terminalResponse?.requestId.uuidString.lowercased() == requestID)
        #expect(snapshot.visibleMessages.filter { $0.role == "assistant" }.count == 1)
        #expect(snapshot.assistantResponses.count == 1)
    }

    @Test func missingTerminalPersistsNoAssistantMessageOrCompanions() async throws {
        let fixture = try await gatewayFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        await #expect(throws: ConversationFailure.retryable) {
            try await GatewayConversationClient(store: fixture.store, deviceID: fixture.deviceID, coaching: UnusedCoachingRunner(), nowMS: { 2 })
                .sendText(conversationID: fixture.conversationID, requestID: "00000000-0000-4000-8000-000000000922", text: "Help me prepare")
        }
        let snapshot = try await ConversationQuery(store: fixture.store).loadConversation(id: fixture.conversationID)
        #expect(snapshot.visibleMessages.filter { $0.role == "assistant" }.isEmpty)
        #expect(snapshot.assistantResponses.isEmpty)
    }
    @Test func fallbackTitleIsDerivedFromTheFirstUserMessage() {
        #expect(
            ConversationTitleDeriver.derive(from: "  Help me prepare for my quarterly performance review next week.  ")
                == "Preparing for their quarterly performance review"
        )
    }

    @Test func fallbackTitleCollapsesWhitespaceAndStaysBounded() throws {
        let title = try #require(ConversationTitleDeriver.derive(
            from: "Plan   the launch\nfor the customer advisory board with clear owners and dates"
        ))

        #expect(title == "Planning the launch for the customer advisory")
        #expect(title.count <= ConversationTitleDeriver.maximumLength)
        #expect(title.split(separator: " ").count < 8)
    }

    @Test func fallbackTitleHandlesAnOverlongFirstToken() throws {
        let title = try #require(ConversationTitleDeriver.derive(from: String(repeating: "a", count: 80)))
        #expect(title.split(separator: " ").count < 8)
        #expect(title == "Discussing")
    }

    @Test func fallbackTitlesAreCompleteReportedPhrases() {
        #expect(ConversationTitleDeriver.derive(from: "If I type now, will it show") == "Checking whether typed messages appear")
        #expect(ConversationTitleDeriver.derive(from: "I'm going to start another one in drafts") == "Starting another conversation draft")
        #expect(ConversationTitleDeriver.derive(from: "I'm recording one last time. I don't know why you") == "Retrying a recording one last time")
        #expect(ConversationTitleDeriver.derive(from: "Why is it that when I try to record, like for some") == "Troubleshooting a recording problem")
        #expect(ConversationTitleDeriver.derive(from: "I'm trying a new one. I don't know why if I tap") == "Testing a new recording attempt")
    }

    @Test func ordinaryTopicsContainingFixtureKeywordsKeepTheirActualSubject() {
        #expect(
            ConversationTitleDeriver.derive(from: "Review my draft promotion packet")
                == "Discussing Review their draft promotion packet"
        )
        #expect(
            ConversationTitleDeriver.derive(from: "We achieved record sales this quarter")
                == "Discussing We achieved record sales this quarter"
        )
    }

    @Test func completedVoiceConversationAppearsInHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(
            at: directory.appendingPathComponent("store.sqlite"),
            keyStore: GatewayConversationTestKeys()
        )
        let conversationID = "00000000-0000-0000-0000-000000000001"
        let deviceID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000099"))
        try await ConversationRepository(store: store).create(
            .init(
                id: conversationID,
                title: "New conversation",
                lifecycle: .draft,
                titleAuthority: .localFallback,
                createdAtMS: 1,
                updatedAtMS: 1
            ),
            context: .init(id: UUID().uuidString, deviceID: deviceID.uuidString, timestamp: 1)
        )
        let client = GatewayConversationClient(
            store: store,
            deviceID: deviceID,
            coaching: UnusedCoachingRunner(),
            nowMS: { 2 }
        )

        try await client.completeVoiceConversation(conversationID: conversationID)

        let index = try await ConversationQuery(store: store).loadIndex()
        #expect(index.conversations.map(\.id) == [conversationID])
        #expect(index.conversations.first?.lifecycle == .completed)
    }

    @Test func loadingHistoryRepairsExistingFallbackTitles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(
            at: directory.appendingPathComponent("store.sqlite"),
            keyStore: GatewayConversationTestKeys()
        )
        let conversationID = "00000000-0000-4000-8000-000000000701"
        let repository = ConversationRepository(store: store)
        let deviceID = "00000000-0000-4000-8000-000000000799"
        try await repository.create(.init(
            id: conversationID,
            title: "New conversation",
            lifecycle: .completed,
            titleAuthority: .localFallback,
            createdAtMS: 1,
            updatedAtMS: 1
        ), context: .init(id: UUID().uuidString, deviceID: deviceID, timestamp: 1))
        try await repository.createMessage(.init(
            id: "00000000-0000-4000-8000-000000000702",
            conversationID: conversationID,
            role: "user",
            body: "Prepare me for the annual planning conversation with leadership",
            createdAtMS: 2
        ), context: .init(id: UUID().uuidString, deviceID: deviceID, timestamp: 2))

        let index = try await ConversationsClient.local(store: store, deviceID: deviceID).load()

        #expect(index.conversations.first?.title == "Preparing for the annual planning conversation")
        #expect(index.conversations.first?.titleAuthority == .localFallback)
        #expect(index.conversations.first?.updatedAtMS == 1)
    }

    @Test func loadingHistoryRepairsGeneratedTitlesButPreservesUserTitles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(
            at: directory.appendingPathComponent("store.sqlite"),
            keyStore: GatewayConversationTestKeys()
        )
        let repository = ConversationRepository(store: store)
        let deviceID = "00000000-0000-4000-8000-000000000899"
        let records: [(String, String, TitleAuthority)] = [
            ("00000000-0000-4000-8000-000000000801", "Leadership planning recap", .assistantSuggested),
            ("00000000-0000-4000-8000-000000000802", "My chosen title", .user),
        ]

        for (offset, record) in records.enumerated() {
            try await repository.create(.init(
                id: record.0,
                title: record.1,
                lifecycle: .completed,
                titleAuthority: record.2,
                createdAtMS: Int64(offset + 1),
                updatedAtMS: Int64(offset + 1)
            ), context: .init(id: UUID().uuidString, deviceID: deviceID, timestamp: Int64(offset + 1)))
            try await repository.createMessage(.init(
                id: "00000000-0000-4000-8000-00000000081\(offset)",
                conversationID: record.0,
                role: "user",
                body: offset == 0
                    ? "Why is it that when I try to record, like for some reason it keeps failing"
                    : "This message would derive a different fallback title",
                createdAtMS: Int64(offset + 10)
            ), context: .init(id: UUID().uuidString, deviceID: deviceID, timestamp: Int64(offset + 10)))
        }

        let index = try await ConversationsClient.local(store: store, deviceID: deviceID).load()
        let titles = Dictionary(uniqueKeysWithValues: index.conversations.map { ($0.id, ($0.title, $0.titleAuthority)) })

        #expect(titles[records[0].0]?.0 == "Troubleshooting a recording problem")
        #expect(titles[records[0].0]?.1 == .localFallback)
        #expect(titles[records[1].0]?.0 == records[1].1)
        #expect(titles[records[1].0]?.1 == .user)
    }
}

private func gatewayFixture() async throws -> (directory: URL, store: TaisaStore, conversationID: String, deviceID: UUID) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: GatewayConversationTestKeys())
    let conversationID = "00000000-0000-4000-8000-000000000920"
    let deviceID = UUID(uuidString: "00000000-0000-4000-8000-000000000999")!
    try await ConversationRepository(store: store).create(
        .init(id: conversationID, title: "New conversation", lifecycle: .draft, titleAuthority: .localFallback, createdAtMS: 1, updatedAtMS: 1),
        context: .init(id: UUID().uuidString, deviceID: deviceID.uuidString, timestamp: 1)
    )
    return (directory, store, conversationID, deviceID)
}
