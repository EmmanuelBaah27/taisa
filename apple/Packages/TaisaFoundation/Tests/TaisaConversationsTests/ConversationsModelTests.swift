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
