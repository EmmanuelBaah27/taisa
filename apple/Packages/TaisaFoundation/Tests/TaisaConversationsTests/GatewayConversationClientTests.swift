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

@Suite(.serialized)
struct GatewayConversationClientTests {
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

    @Test func loadingHistoryPreservesAuthoredAndAssistantSuggestedTitles() async throws {
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
                body: "This message would derive a different fallback title",
                createdAtMS: Int64(offset + 10)
            ), context: .init(id: UUID().uuidString, deviceID: deviceID, timestamp: Int64(offset + 10)))
        }

        let index = try await ConversationsClient.local(store: store, deviceID: deviceID).load()
        let titles = Dictionary(uniqueKeysWithValues: index.conversations.map { ($0.id, ($0.title, $0.titleAuthority)) })

        #expect(titles[records[0].0]?.0 == records[0].1)
        #expect(titles[records[0].0]?.1 == .assistantSuggested)
        #expect(titles[records[1].0]?.0 == records[1].1)
        #expect(titles[records[1].0]?.1 == .user)
    }
}
