import Foundation
import Testing
import TaisaStorage
@testable import TaisaConversations

@MainActor
@Suite("Conversations list model")
struct ConversationsModelTests {
    @Test func draftsRemainSeparateAndNewestFirst() async {
        let drafts = [makeDraft(id: "00000000-0000-0000-0000-000000000011", updated: 30), makeDraft(id: "00000000-0000-0000-0000-000000000012", updated: 10)]
        let conversations = [makeConversation(id: "00000000-0000-0000-0000-000000000021", updated: 40), makeConversation(id: "00000000-0000-0000-0000-000000000022", updated: 20)]
        let model = ConversationsModel(client: ConversationsClient(load: {
            ConversationIndexSnapshot(drafts: drafts.reversed(), conversations: conversations.reversed())
        }))

        await model.load()

        #expect(model.snapshot.drafts.map(\.id) == drafts.map(\.id))
        #expect(model.snapshot.conversations.map(\.id) == conversations.map(\.id))
    }

    @Test func mutationsRefreshFromLocalClient() async {
        let fixture = MutationFixture()
        let model = ConversationsModel(client: await fixture.client())
        await model.load()

        await model.discardDraft(id: "00000000-0000-0000-0000-000000000011")
        await model.renameConversation(id: "00000000-0000-0000-0000-000000000021", title: "Renamed")
        await model.deleteConversation(id: "00000000-0000-0000-0000-000000000021")

        #expect(await fixture.actions == ["discard", "rename:Renamed", "delete"])
    }

    @Test func mutationFailuresRetainTheirRecoveryOperation() async {
        struct MutationFailure: Error {}
        let snapshot = ConversationIndexSnapshot(
            drafts: [makeDraft(id: "draft", updated: 1)],
            conversations: [makeConversation(id: "chat", updated: 1)]
        )
        let model = ConversationsModel(client: ConversationsClient(
            load: { snapshot },
            discardDraft: { _ in throw MutationFailure() },
            renameConversation: { _, _ in throw MutationFailure() },
            deleteConversation: { _ in throw MutationFailure() }
        ))
        await model.load()

        await model.renameConversation(id: "chat", title: "New title")
        #expect(model.state == .content(snapshot, isRefreshing: false, issue: nil))
        #expect(model.notices.map(\.issue) == [.renameFailed(id: "chat", title: "New title")])

        await model.deleteConversation(id: "chat")
        #expect(model.state == .content(snapshot, isRefreshing: false, issue: nil))
        #expect(model.notices.map(\.issue) == [
            .renameFailed(id: "chat", title: "New title"),
            .deleteFailed(id: "chat")
        ])

        await model.discardDraft(id: "draft")
        #expect(model.state == .content(snapshot, isRefreshing: false, issue: nil))
        #expect(model.notices.map(\.issue) == [
            .renameFailed(id: "chat", title: "New title"),
            .deleteFailed(id: "chat"),
            .discardFailed(id: "draft")
        ])
    }

    @Test func retainedRefreshFailureUsesToastAndDismissesInQueueOrder() async throws {
        struct LoadFailure: Error {}
        let snapshot = ConversationIndexSnapshot(
            drafts: [],
            conversations: [makeConversation(id: "chat", updated: 1)]
        )
        let fixture = LoadFixture(results: [.success(snapshot), .failure(LoadFailure())])
        let model = ConversationsModel(client: ConversationsClient(load: { try await fixture.load() }))

        await model.load()
        await model.load()

        #expect(model.state == .content(snapshot, isRefreshing: false, issue: nil))
        #expect(model.notices.map(\.issue) == [.storageUnavailable])
        let firstID = try #require(model.notices.first?.id)
        model.dismissNotice(id: firstID)
        #expect(model.notices.isEmpty)
    }

    @Test func secureRecoveryRemainsBlockingEvenWhenContentWasRetained() async {
        let snapshot = ConversationIndexSnapshot(
            drafts: [],
            conversations: [makeConversation(id: "chat", updated: 1)]
        )
        struct LoadFailure: Error {}
        let fixture = LoadFixture(results: [
            .success(snapshot),
            .failure(LoadFailure()),
            .failure(StorageError.authenticationFailed)
        ])
        let model = ConversationsModel(client: ConversationsClient(load: { try await fixture.load() }))

        await model.load()
        await model.load()
        #expect(model.notices.map(\.issue) == [.storageUnavailable])
        await model.load()

        #expect(model.state == .failure(.recoveryRequired))
        #expect(model.notices.isEmpty)
    }
}

private actor LoadFixture {
    var results: [Result<ConversationIndexSnapshot, any Error>]
    init(results: [Result<ConversationIndexSnapshot, any Error>]) { self.results = results }
    func load() throws -> ConversationIndexSnapshot {
        try results.removeFirst().get()
    }
}

private actor MutationFixture {
    var actions: [String] = []
    func client() -> ConversationsClient {
        ConversationsClient(
            load: { ConversationIndexSnapshot(drafts: [], conversations: []) },
            discardDraft: { [self] _ in await record("discard") },
            renameConversation: { [self] _, title in await record("rename:\(title)") },
            deleteConversation: { [self] _ in await record("delete") }
        )
    }
    func record(_ action: String) { actions.append(action) }
}

private func makeDraft(id: String, updated: Int64) -> ConversationDraftRecord {
    ConversationDraftRecord(
        id: id,
        conversationID: UUID().uuidString,
        inputMode: .text,
        text: "Draft",
        voiceTurnID: nil,
        recoveryKind: .saved,
        createdAtMS: 1,
        updatedAtMS: updated
    )
}

private func makeConversation(id: String, updated: Int64) -> ConversationRecord {
    ConversationRecord(id: id, title: "Conversation", createdAtMS: 1, updatedAtMS: updated)
}
