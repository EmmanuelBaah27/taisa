import XCTest
import TaisaConversations
@testable import Taisa

@MainActor
final class ConversationViewModelTests: XCTestCase {
    func testKeyboardReplacementRequiresDiscardAndCancelRestoresPause() {
        let model = ConversationViewModel.preview(composer: .paused)

        model.requestKeyboard()
        XCTAssertEqual(model.confirmation, .discardVoiceForKeyboard(returnTo: .paused))

        model.cancelConfirmation()
        XCTAssertEqual(model.composer, .paused)
    }

    func testCloseWithInputOffersSaveDiscardCancel() {
        let model = ConversationViewModel.preview(composer: .typing("keep this"))

        model.requestClose()

        XCTAssertEqual(model.confirmation, .saveDiscardOrCancel)
    }

    func testEmptyCloseDismissesWithoutCreatingDraft() {
        var dismissed = 0
        let model = ConversationViewModel.preview(composer: .typing("   "), dismiss: { dismissed += 1 })

        model.requestClose()

        XCTAssertEqual(dismissed, 1)
        XCTAssertNil(model.confirmation)
    }

    func testInitialVoiceIntentIsConsumedOnce() async {
        let client = ConversationScreenClientSpy()
        let model = ConversationViewModel(
            conversationID: UUID().uuidString,
            title: "New conversation",
            entryIntent: .voice,
            client: await client.makeClient()
        )

        await model.start()
        await model.start()

        let beginCount = await client.count()
        XCTAssertEqual(beginCount, 1)
    }
}

private actor ConversationScreenClientSpy {
    private(set) var beginVoiceCount = 0
    func makeClient() -> ConversationScreenClient {
        ConversationScreenClient(
            beginVoice: { [self] in await recordBegin() },
            pauseVoice: {}, resumeVoice: {}, sendVoice: {},
            sendText: { _ in }, retry: {}, saveDraft: { _ in }, discardDraft: {}
        )
    }
    private func recordBegin() { beginVoiceCount += 1 }
    func count() -> Int { beginVoiceCount }
}
