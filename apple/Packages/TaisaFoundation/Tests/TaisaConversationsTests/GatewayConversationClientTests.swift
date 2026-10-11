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
}
