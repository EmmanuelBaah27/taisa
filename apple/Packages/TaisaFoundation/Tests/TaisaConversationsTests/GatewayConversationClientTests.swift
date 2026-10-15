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
}
