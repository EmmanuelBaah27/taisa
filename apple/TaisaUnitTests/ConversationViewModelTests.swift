import XCTest
import TaisaConversations
import TaisaStorage
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

    func testEmptyCloseDismissesWithoutCreatingDraft() async {
        var dismissed = 0
        let model = ConversationViewModel.preview(composer: .typing("   "), dismiss: { dismissed += 1 })

        model.requestClose()
        await Task.yield()

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

    func testVoiceCompletionReloadsMessagesAndWaitsForReply() async {
        let client = ConversationScreenClientSpy()
        let model = ConversationViewModel(
            conversationID: UUID().uuidString,
            title: "New conversation",
            entryIntent: nil,
            composer: .recording,
            client: await client.makeClient(messages: [message(role: "assistant", body: "Ready")])
        )

        await model.sendVoice()

        XCTAssertEqual(model.composer, .waitingForReply)
        XCTAssertEqual(model.messages.map(\.body), ["Ready"])
    }

    func testRetryCompletionReloadsMessagesAndWaitsForReply() async {
        let client = ConversationScreenClientSpy()
        let model = ConversationViewModel(
            conversationID: UUID().uuidString,
            title: "New conversation",
            entryIntent: nil,
            composer: .failure(.retryable),
            client: await client.makeClient(messages: [message(role: "assistant", body: "Recovered")])
        )

        await model.retry()

        XCTAssertEqual(model.composer, .waitingForReply)
        XCTAssertEqual(model.messages.map(\.body), ["Recovered"])
    }

    func testFailedCorrectionRemainsAvailableForRetry() async {
        let client = ConversationScreenClientSpy(correctionFails: true)
        let model = ConversationViewModel(
            conversationID: UUID().uuidString, title: "New conversation", entryIntent: nil,
            client: await client.makeClient()
        )
        let original = message(role: "user", body: "Original")
        model.requestCorrection(original)
        model.correctionText = "Corrected"

        await model.submitCorrection()

        XCTAssertEqual(model.composer, .failure(.retryable))
        XCTAssertEqual(model.correctionMessageID, original.id)
        XCTAssertEqual(model.correctionText, "Corrected")
    }

    func testFailedTextSendSavesAsTextDraft() async {
        let client = ConversationScreenClientSpy()
        let model = ConversationViewModel(
            conversationID: UUID().uuidString, title: "New conversation", entryIntent: nil,
            composer: .failure(.retryable), text: "Keep this text",
            client: await client.makeClient()
        )

        await model.saveAndClose()

        let saved = await client.savedInput()
        XCTAssertEqual(saved, .text("Keep this text"))
    }

    private func message(role: String, body: String) -> MessageRecord {
        MessageRecord(
            id: UUID().uuidString, conversationID: UUID().uuidString,
            role: role, body: body, createdAtMS: 1
        )
    }
}

private actor ConversationScreenClientSpy {
    let messages: [MessageRecord]
    let correctionFails: Bool
    private(set) var beginVoiceCount = 0
    private var saved: ConversationInput?

    init(messages: [MessageRecord] = [], correctionFails: Bool = false) {
        self.messages = messages
        self.correctionFails = correctionFails
    }

    func makeClient(messages: [MessageRecord]? = nil) -> ConversationScreenClient {
        let loaded = messages ?? self.messages
        return ConversationScreenClient(
            loadMessages: { loaded },
            beginVoice: { [self] in await recordBegin() },
            pauseVoice: {}, resumeVoice: {}, sendVoice: {},
            sendText: { _ in }, retry: {}, saveDraft: { [self] input in await save(input) }, discardDraft: {},
            correctTranscript: { [correctionFails] _, _ in
                if correctionFails { throw ConversationFailure.retryable }
            }
        )
    }
    private func recordBegin() { beginVoiceCount += 1 }
    private func save(_ input: ConversationInput) { saved = input }
    func count() -> Int { beginVoiceCount }
    func savedInput() -> ConversationInput? { saved }
}
