import XCTest
import TaisaConversations
import TaisaAudio
import TaisaStorage
import TaisaVoice
@testable import Taisa

@MainActor
final class ConversationViewModelTests: XCTestCase {
    func testStartRefreshesPersistedConversationTitle() async {
        let client = ConversationScreenClient(
            loadTitle: { "Persisted conversation title" },
            beginVoice: {}, pauseVoice: {}, resumeVoice: {}, sendVoice: { _ in },
            sendText: { _ in }, retry: {}, saveDraft: { _ in }, discardDraft: {}
        )
        let model = ConversationViewModel(
            conversationID: UUID().uuidString,
            title: "Stale route title",
            entryIntent: nil,
            client: client
        )

        await model.start()

        XCTAssertEqual(model.title, "Persisted conversation title")
    }

    func testTimelineMotionDisablesNewMessageAnimationWhenReduceMotionIsEnabled() {
        XCTAssertFalse(ConversationTimelineMotion.animatesNewMessage(reduceMotion: true))
        XCTAssertTrue(ConversationTimelineMotion.animatesNewMessage(reduceMotion: false))
    }

    func testNonemptyKeyboardReplacementRequiresDiscardAndCancelRestoresPause() async {
        let client = ConversationScreenClientSpy(captureDisposition: .sendable)
        let model = ConversationViewModel(
            conversationID: UUID().uuidString, title: "Chat", entryIntent: nil,
            composer: .paused, client: await client.makeClient()
        )
        await model.start()

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

    func testShortCaptureCloseOffersDiscardOrKeepRecordingWithoutSave() async {
        let client = ConversationScreenClientSpy(captureDisposition: .shortCapture)
        let model = ConversationViewModel(
            conversationID: UUID().uuidString, title: "Chat", entryIntent: nil,
            composer: .recording, client: await client.makeClient()
        )
        await model.start()

        model.requestClose()

        XCTAssertEqual(model.confirmation, .discardShortOrKeepRecording)
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

    func testInitialVoiceFailureKeepsStartRecordingRecoveryContext() async {
        struct StartFailure: Error {}
        let client = ConversationScreenClient(
            beginVoice: { throw StartFailure() }, pauseVoice: {}, resumeVoice: {},
            sendVoice: { _ in }, sendText: { _ in }, retry: {},
            saveDraft: { _ in }, discardDraft: {}
        )
        let model = ConversationViewModel(
            conversationID: UUID().uuidString, title: "New conversation",
            entryIntent: .voice, client: client
        )

        await model.start()

        XCTAssertEqual(model.composer, .failure(.unavailable))
        XCTAssertEqual(model.failureContext, .beginRecording)
    }

    func testDeniedMicrophoneUsesSettingsRecoveryContext() async {
        let client = ConversationScreenClient(
            beginVoice: { throw AudioCaptureError.permissionDenied },
            pauseVoice: {}, resumeVoice: {}, sendVoice: { _ in },
            sendText: { _ in }, retry: {}, saveDraft: { _ in }, discardDraft: {}
        )
        let model = ConversationViewModel(
            conversationID: UUID().uuidString, title: "New conversation",
            entryIntent: .voice, client: client
        )

        await model.start()

        XCTAssertEqual(model.failureContext, .microphonePermissionDenied)
    }

    func testDeniedMicrophoneCanContinueInKeyboardMode() async {
        let client = ConversationScreenClient(
            beginVoice: { throw AudioCaptureError.permissionDenied },
            pauseVoice: {}, resumeVoice: {}, sendVoice: { _ in },
            sendText: { _ in }, retry: {}, saveDraft: { _ in }, discardDraft: {}
        )
        let model = ConversationViewModel(
            conversationID: UUID().uuidString,
            title: "New conversation",
            entryIntent: nil,
            client: client
        )
        try? await model.beginVoice()

        model.continueWithKeyboardAfterPermissionDenial()

        XCTAssertEqual(model.composer, .typing(""))
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

    func testVoiceTranscriptAppearsBeforeCoachingCompletes() async {
        let transcriptShown = AsyncGate()
        let finishCoaching = AsyncGate()
        let messages = MessageSequence([
            [message(role: "user", body: "Recorded words")],
            [
                message(role: "user", body: "Recorded words"),
                message(role: "assistant", body: "Coaching reply"),
            ],
        ])
        let client = ConversationScreenClient(
            loadMessages: { await messages.next() },
            beginVoice: {}, pauseVoice: {}, resumeVoice: {},
            sendVoice: { transcriptAvailable in
                await transcriptAvailable()
                await transcriptShown.open()
                await finishCoaching.wait()
            },
            sendText: { _ in }, retry: {}, saveDraft: { _ in }, discardDraft: {}
        )
        let model = ConversationViewModel(
            conversationID: UUID().uuidString,
            title: "New conversation",
            entryIntent: nil,
            composer: .recording,
            client: client
        )

        let send = Task { await model.sendVoice() }
        await transcriptShown.wait()

        XCTAssertEqual(model.composer, .coaching)
        XCTAssertEqual(model.messages.map(\.body), ["Recorded words"])
        XCTAssertEqual(model.latestUserTranscript, "Recorded words")

        await finishCoaching.open()
        await send.value
        XCTAssertEqual(model.composer, .waitingForReply)
        XCTAssertEqual(model.messages.map(\.body), ["Recorded words", "Coaching reply"])
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
        let original = message(role: "user", body: "Original")
        let model = ConversationViewModel(
            conversationID: original.conversationID, title: "New conversation", entryIntent: nil,
            client: await client.makeClient(messages: [original])
        )
        await model.start()
        model.requestCorrection(original)
        model.correctionText = "Corrected"

        await model.submitCorrection()

        XCTAssertEqual(model.composer, .failure(.retryable))
        XCTAssertEqual(model.correctionMessageID, original.id)
        XCTAssertEqual(model.correctionText, "Corrected")
        XCTAssertEqual(model.messages.first?.body, "Corrected")
    }

    func testCorrectionRetryReusesPendingRequestInsteadOfCreatingAnotherCorrection() async {
        let client = ConversationScreenClientSpy(correctionFails: true)
        let original = message(role: "user", body: "Original")
        let model = ConversationViewModel(
            conversationID: original.conversationID, title: "Chat", entryIntent: nil,
            client: await client.makeClient(messages: [original])
        )
        await model.start()
        model.requestCorrection(original)
        model.correctionText = "Corrected"

        await model.submitCorrection()
        model.correctionText = "A different correction"
        XCTAssertFalse(model.canSubmitCorrection)
        model.correctionText = "Corrected"
        await model.submitCorrection()

        let counts = await client.correctionRequestCounts()
        XCTAssertEqual(counts, [1, 1])
        XCTAssertNil(model.correctionMessageID)
    }

    func testCancellingFailedCorrectionDoesNotAllowReplacingPendingRequest() async {
        let client = ConversationScreenClientSpy(correctionFails: true)
        let original = message(role: "user", body: "Original")
        let model = ConversationViewModel(
            conversationID: original.conversationID, title: "Chat", entryIntent: nil,
            client: await client.makeClient(messages: [original])
        )
        await model.start()
        model.requestCorrection(original)
        model.correctionText = "First correction"
        await model.submitCorrection()

        model.cancelCorrection()
        model.requestCorrection(original)

        XCTAssertNil(model.correctionMessageID)

        await model.retry()
        model.requestCorrection(original)

        XCTAssertEqual(model.correctionMessageID, original.id)
    }

    func testCorrectionRequiresUserMessageAndChangedNonemptyText() {
        let user = message(role: "user", body: "Complete original text")
        let assistant = message(role: "assistant", body: "Reply")
        let model = ConversationViewModel.preview(composer: .waitingForReply, messages: [user, assistant])

        model.requestCorrection(assistant)
        XCTAssertNil(model.correctionMessageID)
        model.requestCorrection(user)
        XCTAssertEqual(model.correctionText, "Complete original text")
        XCTAssertFalse(model.canSubmitCorrection)
        model.correctionText = "   "
        XCTAssertFalse(model.canSubmitCorrection)
        model.correctionText = "Corrected complete text"
        XCTAssertTrue(model.canSubmitCorrection)
    }

    func testOnlyOneCorrectionCanBeEditedAtATime() {
        let first = message(role: "user", body: "First")
        let second = message(role: "user", body: "Second")
        let model = ConversationViewModel.preview(composer: .waitingForReply, messages: [first, second])
        model.requestCorrection(first)
        model.requestCorrection(second)
        XCTAssertEqual(model.correctionMessageID, first.id)
        XCTAssertEqual(model.correctionText, "First")
    }

    func testCaptureDispositionDrivesApprovedPagePhases() async {
        let cases: [(VoiceCaptureDisposition, ConversationViewModel.PagePhase)] = [
            (.empty, .empty), (.shortCapture, .shortCapture), (.sendable, .sendable),
        ]
        for (disposition, expected) in cases {
            let client = ConversationScreenClientSpy(captureDisposition: disposition)
            let model = ConversationViewModel(
                conversationID: UUID().uuidString, title: "New chat", entryIntent: nil,
                composer: .recording, client: await client.makeClient()
            )
            await model.start()
            XCTAssertEqual(model.pagePhase, expected)
        }
        XCTAssertEqual(ConversationViewModel.preview(composer: .paused).pagePhase, .paused)
        XCTAssertEqual(ConversationViewModel.preview(composer: .savedVoiceDraft).pagePhase, .saved)
        XCTAssertEqual(ConversationViewModel.preview(composer: .typing("")).pagePhase, .text)
        XCTAssertEqual(ConversationViewModel.preview(composer: .transcribing).pagePhase, .durableProcessing)
    }

    func testEmptyRecordingDiscardCleansUpProvisionalChatAndDismisses() async {
        let client = ConversationScreenClientSpy(captureDisposition: .empty)
        var dismissed = 0
        let model = ConversationViewModel(
            conversationID: UUID().uuidString, title: "New chat", entryIntent: nil,
            composer: .recording, client: await client.makeClient(), dismiss: { dismissed += 1 }
        )
        await model.start()
        await model.confirmDiscardRecording()
        let counts = await client.discardCounts()
        XCTAssertEqual(counts, [1, 1])
        XCTAssertEqual(dismissed, 1)
    }

    func testCancelRecoveryClosesWithoutDiscardingRecoverableInput() async {
        let client = ConversationScreenClientSpy()
        var dismissed = 0
        let model = ConversationViewModel(
            conversationID: UUID().uuidString, title: "Chat", entryIntent: nil,
            composer: .failure(.retryable), client: await client.makeClient(), dismiss: { dismissed += 1 }
        )
        model.cancelRecoveryAndClose()
        let counts = await client.discardCounts()
        XCTAssertEqual(counts, [0, 0])
        XCTAssertEqual(dismissed, 1)
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

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor MessageSequence {
    private let snapshots: [[MessageRecord]]
    private var index = 0

    init(_ snapshots: [[MessageRecord]]) { self.snapshots = snapshots }

    func next() -> [MessageRecord] {
        let value = snapshots[min(index, snapshots.count - 1)]
        index += 1
        return value
    }
}

private actor ConversationScreenClientSpy {
    let messages: [MessageRecord]
    let correctionFails: Bool
    private(set) var beginVoiceCount = 0
    private var saved: ConversationInput?
    private let captureDisposition: VoiceCaptureDisposition
    private var discardedDraftCount = 0
    private var discardedConversationCount = 0
    private var correctionRequestCount = 0
    private var retryCount = 0

    init(messages: [MessageRecord] = [], correctionFails: Bool = false, captureDisposition: VoiceCaptureDisposition = .empty) {
        self.messages = messages
        self.correctionFails = correctionFails
        self.captureDisposition = captureDisposition
    }

    func makeClient(messages: [MessageRecord]? = nil) -> ConversationScreenClient {
        let loaded = messages ?? self.messages
        return ConversationScreenClient(
            loadMessages: { loaded },
            beginVoice: { [self] in await recordBegin() },
            pauseVoice: {}, resumeVoice: {}, sendVoice: { _ in },
            sendText: { _ in }, retry: { [self] in await recordRetry() }, saveDraft: { [self] input in await save(input) },
            discardDraft: { [self] in await recordDraftDiscard() },
            discardEmptyConversation: { [self] in await recordConversationDiscard() },
            correctTranscript: { [self, correctionFails] _, _ in
                await recordCorrectionRequest()
                if correctionFails { throw ConversationFailure.retryable }
            },
            loadCaptureSnapshot: { [captureDisposition] in
                .init(activity: .recording, elapsedMilliseconds: 0, meter: .init(averagePower: -160, peakPower: -160), disposition: captureDisposition)
            }
        )
    }
    private func recordBegin() { beginVoiceCount += 1 }
    private func save(_ input: ConversationInput) { saved = input }
    func count() -> Int { beginVoiceCount }
    func savedInput() -> ConversationInput? { saved }
    private func recordDraftDiscard() { discardedDraftCount += 1 }
    private func recordConversationDiscard() { discardedConversationCount += 1 }
    func discardCounts() -> [Int] { [discardedDraftCount, discardedConversationCount] }
    private func recordCorrectionRequest() { correctionRequestCount += 1 }
    private func recordRetry() { retryCount += 1 }
    func correctionRequestCounts() -> [Int] { [correctionRequestCount, retryCount] }
}
