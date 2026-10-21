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
            sendText: { _, available in await available() }, retry: {}, saveDraft: { _ in }, discardDraft: {}
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

    func testPreviewKeepsSeededAssistantResponsesAfterStart() async {
        let messageID = UUID().uuidString
        let response = AssistantResponseRecord(
            metadata: AssistantResponseMetadataRecord(
                responseMessageID: messageID,
                requestID: UUID().uuidString,
                idempotencyReceipt: "preview-receipt",
                mode: .coach,
                relevance: "career-relevant",
                contextSufficiency: "sufficient",
                stance: "nudge",
                inference: "A useful inference.",
                confidence: "high",
                approach: "Offer one grounded next step.",
                createdAtMS: 1
            ),
            sources: [], proposal: nil, feedback: nil
        )
        let model = ConversationViewModel.preview(
            composer: .waitingForReply,
            assistantResponses: [messageID: response]
        )

        await model.start()

        XCTAssertNotNil(model.assistantResponses[messageID])
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

    func testKeyboardReplacementSurvivesDialogDismissalBeforeAsyncActionStarts() async {
        let client = ConversationScreenClientSpy(captureDisposition: .sendable)
        let model = ConversationViewModel(
            conversationID: UUID().uuidString, title: "Chat", entryIntent: nil,
            composer: .recording, client: await client.makeClient()
        )
        await model.start()

        model.requestKeyboard()
        XCTAssertEqual(model.confirmation, .discardVoiceForKeyboard(returnTo: .recording))

        // SwiftUI dismisses a confirmation dialog before the Task created by
        // its selected button is guaranteed to start.
        model.cancelConfirmation()
        await model.confirmKeyboardReplacement()

        XCTAssertEqual(model.composer, .typing(""))
        XCTAssertNil(model.confirmation)
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
            sendVoice: { _ in }, sendText: { _, available in await available() }, retry: {},
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
            sendText: { _, available in await available() }, retry: {}, saveDraft: { _ in }, discardDraft: {}
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
            sendText: { _, available in await available() }, retry: {}, saveDraft: { _ in }, discardDraft: {}
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

    func testRecordingStartFailureCanContinueInKeyboardMode() async {
        struct StartFailure: Error {}
        let client = ConversationScreenClient(
            beginVoice: { throw StartFailure() }, pauseVoice: {}, resumeVoice: {},
            sendVoice: { _ in }, sendText: { _, available in await available() }, retry: {},
            saveDraft: { _ in }, discardDraft: {}
        )
        let model = ConversationViewModel(
            conversationID: UUID().uuidString,
            title: "New conversation",
            entryIntent: nil,
            client: client
        )
        try? await model.beginVoice()

        model.continueWithKeyboardAfterRecordingFailure()

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

        XCTAssertEqual(model.composer, .coaching)
        XCTAssertEqual(model.messages.map(\.body), ["Ready"])
        model.completeStreamingPresentation()
        XCTAssertEqual(model.composer, .waitingForReply)
    }

    func testVoiceFailureBeforeTranscriptUsesTranscriptionRecovery() async {
        struct VoiceFailure: Error {}
        let client = ConversationScreenClient(
            beginVoice: {}, pauseVoice: {}, resumeVoice: {},
            sendVoice: { _ in throw VoiceFailure() },
            sendText: { _, available in await available() }, retry: {},
            saveDraft: { _ in }, discardDraft: {}
        )
        let model = ConversationViewModel(
            conversationID: UUID().uuidString, title: "Chat", entryIntent: nil,
            composer: .recording, client: client
        )

        await model.sendVoice()

        XCTAssertEqual(model.failureContext, .transcription)
    }

    func testVoiceFailureAfterTranscriptUsesResponseRecovery() async {
        struct VoiceFailure: Error {}
        let client = ConversationScreenClient(
            beginVoice: {}, pauseVoice: {}, resumeVoice: {},
            sendVoice: { transcriptAvailable in
                await transcriptAvailable()
                throw VoiceFailure()
            },
            sendText: { _, available in await available() }, retry: {}, saveDraft: { _ in }, discardDraft: {}
        )
        let model = ConversationViewModel(
            conversationID: UUID().uuidString, title: "Chat", entryIntent: nil,
            composer: .recording, client: client
        )

        await model.sendVoice()

        XCTAssertEqual(model.failureContext, .request)
    }

    func testTextResponseFailureReloadsTheSavedUserMessage() async {
        struct ResponseFailure: Error {}
        let savedMessage = message(role: "user", body: "My saved typed message")
        let client = ConversationScreenClient(
            loadMessages: { [savedMessage] },
            beginVoice: {}, pauseVoice: {}, resumeVoice: {},
            sendVoice: { _ in },
            sendText: { _, available in await available(); throw ResponseFailure() },
            retry: {}, saveDraft: { _ in }, discardDraft: {}
        )
        let model = ConversationViewModel(
            conversationID: savedMessage.conversationID,
            title: "New conversation",
            entryIntent: nil,
            composer: .typing("My saved typed message"),
            text: "My saved typed message",
            client: client
        )

        await model.sendText()

        XCTAssertEqual(model.failureContext, .request)
        XCTAssertEqual(model.messages.map(\.body), ["My saved typed message"])
        XCTAssertEqual(model.text, "")
    }

    func testTextSendDoesNotReturnToReplyWithoutAnAssistantResponse() async {
        let savedMessage = message(role: "user", body: "Persisted but unanswered")
        let client = ConversationScreenClient(
            loadMessages: { [savedMessage] },
            beginVoice: {}, pauseVoice: {}, resumeVoice: {}, sendVoice: { _ in },
            sendText: { _, available in await available() },
            retry: {}, saveDraft: { _ in }, discardDraft: {}
        )
        let model = ConversationViewModel(
            conversationID: savedMessage.conversationID,
            title: "Chat",
            entryIntent: nil,
            composer: .typing(savedMessage.body),
            text: savedMessage.body,
            client: client
        )

        await model.sendText()

        XCTAssertEqual(model.composer, .failure(.retryable))
        XCTAssertEqual(model.failureContext, .request)
        XCTAssertEqual(model.messages.map(\.body), [savedMessage.body])
    }

    func testTextPersistenceFailureDoesNotDiscardUnsentText() async {
        struct PersistenceFailure: Error {}
        let client = ConversationScreenClient(
            loadMessages: { [] },
            beginVoice: {}, pauseVoice: {}, resumeVoice: {}, sendVoice: { _ in },
            sendText: { _, _ in throw PersistenceFailure() },
            retry: {}, saveDraft: { _ in }, discardDraft: {}
        )
        let model = ConversationViewModel(
            conversationID: UUID().uuidString,
            title: "Chat",
            entryIntent: nil,
            composer: .typing("Unsent thought"),
            text: "Unsent thought",
            client: client
        )

        await model.sendText()

        XCTAssertEqual(model.text, "Unsent thought")
        XCTAssertTrue(model.messages.isEmpty)
    }

    func testTypedMessageAppearsBeforeCoachingCompletes() async {
        let messageShown = AsyncGate()
        let finishCoaching = AsyncGate()
        let messages = MessageSequence([
            [message(role: "user", body: "Typed follow-up")],
            [
                message(role: "user", body: "Typed follow-up"),
                message(role: "assistant", body: "Coaching reply"),
            ],
        ])
        let client = ConversationScreenClient(
            loadMessages: { await messages.next() },
            beginVoice: {}, pauseVoice: {}, resumeVoice: {}, sendVoice: { _ in },
            sendText: { _, messageAvailable in
                await messageAvailable()
                await messageShown.open()
                await finishCoaching.wait()
            },
            retry: {}, saveDraft: { _ in }, discardDraft: {}
        )
        let model = ConversationViewModel(
            conversationID: UUID().uuidString,
            title: "Chat",
            entryIntent: nil,
            composer: .typing("Typed follow-up"),
            text: "Typed follow-up",
            client: client
        )

        let send = Task { await model.sendText() }
        await messageShown.wait()

        XCTAssertEqual(model.composer, .coaching)
        XCTAssertEqual(model.messages.map(\.body), ["Typed follow-up"])
        XCTAssertEqual(model.text, "")

        await finishCoaching.open()
        await send.value
        XCTAssertEqual(model.composer, .coaching)
        XCTAssertEqual(model.messages.map(\.body), ["Typed follow-up", "Coaching reply"])
        model.completeStreamingPresentation()
        XCTAssertEqual(model.composer, .waitingForReply)
    }

    func testTypedSendRetainsComposerContentUntilDurableMessageIsAvailable() async {
        let allowMessage = AsyncGate()
        let messageShown = AsyncGate()
        let user = message(role: "user", body: "Move into the bubble")
        let client = ConversationScreenClient(
            loadMessages: { [user] },
            beginVoice: {}, pauseVoice: {}, resumeVoice: {}, sendVoice: { _ in },
            sendText: { _, messageAvailable in
                await allowMessage.wait()
                await messageAvailable()
                await messageShown.open()
            },
            retry: {}, saveDraft: { _ in }, discardDraft: {}
        )
        let model = ConversationViewModel(
            conversationID: user.conversationID, title: "Chat", entryIntent: nil,
            composer: .typing("Move into the bubble"), text: "Move into the bubble", client: client
        )

        let send = Task { await model.sendText() }
        for _ in 0..<100 where !model.isSendingText { await Task.yield() }
        XCTAssertTrue(model.isSendingText)
        XCTAssertEqual(model.text, "Move into the bubble")
        XCTAssertNil(model.transitioningUserMessageID)

        await allowMessage.open()
        await messageShown.wait()
        XCTAssertEqual(model.text, "")
        XCTAssertEqual(model.transitioningUserMessageID, user.id)
        await send.value
    }

    func testShortCompletedResponseRemainsStreamingUntilRevealFinishes() async {
        let user = message(role: "user", body: "Short question")
        let assistant = message(role: "assistant", body: "Short answer")
        let messages = MessageSequence([[user], [user, assistant]])
        let client = ConversationScreenClient(
            loadMessages: { await messages.next() },
            beginVoice: {}, pauseVoice: {}, resumeVoice: {}, sendVoice: { _ in },
            sendText: { _, messageAvailable in await messageAvailable() },
            retry: {}, saveDraft: { _ in }, discardDraft: {},
            loadPartialCoaching: { "Short answer" }
        )
        let model = ConversationViewModel(
            conversationID: user.conversationID, title: "Chat", entryIntent: nil,
            composer: .typing("Short question"), text: "Short question", client: client
        )

        await model.sendText()

        XCTAssertEqual(model.composer, .coaching)
        XCTAssertEqual(model.partialCoaching, "Short answer")
        XCTAssertEqual(model.streamingFinalMessageID, assistant.id)

        model.completeStreamingPresentation()

        XCTAssertEqual(model.composer, .waitingForReply)
        XCTAssertEqual(model.partialCoaching, "")
        XCTAssertNil(model.streamingFinalMessageID)
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
            sendText: { _, available in await available() }, retry: {}, saveDraft: { _ in }, discardDraft: {}
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
        XCTAssertEqual(model.composer, .coaching)
        XCTAssertEqual(model.messages.map(\.body), ["Recorded words", "Coaching reply"])
        model.completeStreamingPresentation()
        XCTAssertEqual(model.composer, .waitingForReply)
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

    func testRetryDoesNotHideRecoveryWhenNoAssistantResponseWasPersisted() async {
        let unanswered = message(role: "user", body: "Still waiting")
        let client = ConversationScreenClient(
            loadMessages: { [unanswered] },
            beginVoice: {}, pauseVoice: {}, resumeVoice: {}, sendVoice: { _ in },
            sendText: { _, available in await available() },
            retry: {}, saveDraft: { _ in }, discardDraft: {}
        )
        let model = ConversationViewModel(
            conversationID: unanswered.conversationID,
            title: "Chat",
            entryIntent: nil,
            composer: .failure(.retryable),
            client: client
        )

        await model.retry()

        XCTAssertEqual(model.composer, .failure(.retryable))
        XCTAssertEqual(model.failureContext, .request)
    }

    func testRecoveryEventDoesNotHideRetryWhenAssistantResponseIsStillMissing() async {
        let unanswered = message(role: "user", body: "Recovered transport, missing response")
        let (events, continuation) = AsyncStream<Void>.makeStream()
        let client = ConversationScreenClient(
            loadMessages: { [unanswered] },
            beginVoice: {}, pauseVoice: {}, resumeVoice: {}, sendVoice: { _ in },
            sendText: { _, available in await available() },
            retry: {}, saveDraft: { _ in }, discardDraft: {},
            recoveryEvents: { events }
        )
        let model = ConversationViewModel(
            conversationID: unanswered.conversationID,
            title: "Chat",
            entryIntent: nil,
            composer: .coaching,
            client: client
        )
        await model.start()

        continuation.yield(())
        for _ in 0..<100 where model.composer == .coaching { await Task.yield() }

        XCTAssertEqual(model.composer, .failure(.retryable))
        XCTAssertEqual(model.failureContext, .request)
        continuation.finish()
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
        let regenerated = message(role: "assistant", body: "Regenerated reply")
        let model = ConversationViewModel(
            conversationID: original.conversationID, title: "Chat", entryIntent: nil,
            client: await client.makeClient(messages: [original, regenerated])
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

    func testTypedSendRetainsComposerBeforeDurableCommitCompletes() async {
        let gate = AsyncGate()
        let events = EventRecorder()
        let client = ConversationScreenClient(
            beginVoice: {}, pauseVoice: {}, resumeVoice: {}, sendVoice: { _ in },
            sendText: { _, available in
                await events.append("send-start")
                await gate.wait()
                await available()
            },
            retry: {}, saveDraft: { _ in }, discardDraft: {}
        )
        let model = ConversationViewModel(
            conversationID: UUID().uuidString, title: "Chat", entryIntent: nil,
            composer: .typing("Send once"), text: "Send once", client: client
        )

        let send = Task { await model.sendText() }
        while !(await events.values()).contains("send-start") { await Task.yield() }

        XCTAssertEqual(model.text, "Send once")
        XCTAssertEqual(model.composer, .coaching)
        await gate.open()
        await send.value
    }

    func testCloseWaitsUntilTypedMessageIsDurable() async {
        let durableGate = AsyncGate()
        let durableCallback = AsyncGate()
        let finishGate = AsyncGate()
        var dismissed = 0
        let client = ConversationScreenClient(
            beginVoice: {}, pauseVoice: {}, resumeVoice: {}, sendVoice: { _ in },
            sendText: { _, available in
                await durableGate.wait()
                await available()
                await durableCallback.open()
                await finishGate.wait()
            }, retry: {}, saveDraft: { _ in }, discardDraft: {}
        )
        let model = ConversationViewModel(
            conversationID: UUID().uuidString, title: "Chat", entryIntent: nil,
            composer: .typing("Durable first"), text: "Durable first", client: client,
            dismiss: { dismissed += 1 }
        )

        let send = Task { await model.sendText() }
        await Task.yield()
        model.requestClose()
        XCTAssertEqual(dismissed, 0)

        await durableGate.open()
        await durableCallback.wait()
        model.requestClose()
        XCTAssertEqual(dismissed, 1)
        await finishGate.open()
        await send.value
    }

    func testFeedbackFailureDoesNotReplaceComposerWithCoachingFailure() async {
        let client = ConversationScreenClient(
            beginVoice: {}, pauseVoice: {}, resumeVoice: {}, sendVoice: { _ in },
            sendText: { _, available in await available() }, retry: {},
            saveDraft: { _ in }, discardDraft: {},
            saveFeedback: { _ in throw ConversationFailure.retryable }
        )
        let model = ConversationViewModel(
            conversationID: UUID().uuidString, title: "Chat", entryIntent: nil,
            composer: .waitingForReply, client: client
        )

        await model.saveFeedback(
            responseMessageID: UUID().uuidString, direction: .helpful,
            factors: [.coverage], detail: nil
        )

        XCTAssertEqual(model.composer, .waitingForReply)
        XCTAssertEqual(model.responseActionFailure?.message, "Couldn’t save feedback. Try again.")
    }

    func testResponseActionFailuresQueueAndRetryTheirExactActions() async {
        let calls = ResponseActionCallSpy()
        let firstID = UUID().uuidString
        let secondID = UUID().uuidString
        let client = ConversationScreenClient(
            beginVoice: {}, pauseVoice: {}, resumeVoice: {}, sendVoice: { _ in },
            sendText: { _, available in await available() }, retry: {},
            saveDraft: { _ in }, discardDraft: {},
            acceptProposal: { id in
                if await calls.record(id) == 1 { throw ConversationFailure.retryable }
            },
            dismissProposal: { id in
                if await calls.record(id) == 1 { throw ConversationFailure.retryable }
            }
        )
        let model = ConversationViewModel(
            conversationID: UUID().uuidString, title: "Chat", entryIntent: nil,
            composer: .waitingForReply, client: client
        )

        await model.acceptProposal(firstID)
        await model.dismissProposal(secondID)

        XCTAssertEqual(model.responseActionFailures.map(\.id), ["accept:\(firstID)", "dismiss:\(secondID)"])
        await model.retryFailedResponseAction()
        XCTAssertEqual(model.responseActionFailures.map(\.id), ["dismiss:\(secondID)"])
        let firstCallCount = await calls.count(firstID)
        XCTAssertEqual(firstCallCount, 2)
    }

    func testFailedRepeatedTextDoesNotTreatHistoricalMessageAsCurrentSend() async {
        let existing = MessageRecord(
            id: UUID().uuidString, conversationID: UUID().uuidString,
            role: "user", body: "Same words", createdAtMS: 1
        )
        let client = ConversationScreenClient(
            loadMessages: { [existing] },
            beginVoice: {}, pauseVoice: {}, resumeVoice: {}, sendVoice: { _ in },
            sendText: { _, _ in throw ConversationFailure.retryable },
            retry: {}, saveDraft: { _ in }, discardDraft: {}
        )
        let model = ConversationViewModel(
            conversationID: existing.conversationID, title: "Chat", entryIntent: nil,
            composer: .typing("Same words"), text: "Same words", client: client
        )
        await model.start()

        await model.sendText()

        XCTAssertEqual(model.composer, .typing("Same words"))
        XCTAssertEqual(model.text, "Same words")
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

    func testChevronOnRetryableFailureWithDurableMessageOffersSaveDiscardOrStay() async {
        let user = message(role: "user", body: "Already saved")
        var dismissed = 0
        let client = ConversationScreenClient(
            loadMessages: { [user] },
            beginVoice: {}, pauseVoice: {}, resumeVoice: {}, sendVoice: { _ in },
            sendText: { _, available in await available() }, retry: {},
            saveDraft: { _ in }, discardDraft: {}
        )
        let model = ConversationViewModel(
            conversationID: user.conversationID, title: "Chat", entryIntent: nil,
            composer: .failure(.retryable), client: client, dismiss: { dismissed += 1 }
        )
        await model.start()

        model.requestClose()

        XCTAssertEqual(model.confirmation, .saveDiscardOrCancel)
        XCTAssertEqual(dismissed, 0)
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

    func testFeedbackSavePersistsOptionalTypedDetail() async {
        let client = ConversationScreenClientSpy()
        let model = ConversationViewModel(
            conversationID: UUID().uuidString, title: "New conversation", entryIntent: nil,
            client: await client.makeClient()
        )
        let responseID = UUID().uuidString

        await model.saveFeedback(
            responseMessageID: responseID,
            direction: .notHelpful,
            factors: [.communicationClarity, .intentAlignment],
            detail: "It sounded more formal than this conversation."
        )

        let saved = await client.savedFeedback()
        XCTAssertEqual(saved?.responseMessageID, UUID(uuidString: responseID)?.uuidString)
        XCTAssertEqual(saved?.direction, .notHelpful)
        XCTAssertEqual(saved?.factors, [.communicationClarity, .intentAlignment])
        XCTAssertEqual(saved?.detail, "It sounded more formal than this conversation.")
    }

    func testRemovingSelectedFeedbackDeletesTheLocalRating() async {
        let client = ConversationScreenClientSpy()
        let model = ConversationViewModel(
            conversationID: UUID().uuidString, title: "New conversation", entryIntent: nil,
            client: await client.makeClient()
        )
        let responseID = UUID().uuidString

        await model.saveFeedback(responseMessageID: responseID, direction: nil, factors: [], detail: nil)

        let removedFeedbackID = await client.removedFeedbackID()
        XCTAssertEqual(removedFeedbackID, UUID(uuidString: responseID)?.uuidString)
    }

    func testFeedbackSaveAndRemovalAreSerializedInTapOrder() async {
        let gate = AsyncGate()
        let events = EventRecorder()
        let client = ConversationScreenClient(
            beginVoice: {}, pauseVoice: {}, resumeVoice: {}, sendVoice: { _ in },
            sendText: { _, available in await available() }, retry: {}, saveDraft: { _ in }, discardDraft: {},
            saveFeedback: { _ in
                await events.append("save-start")
                await gate.wait()
                await events.append("save-end")
            },
            removeFeedback: { _, _ in await events.append("remove") }
        )
        let model = ConversationViewModel(
            conversationID: UUID().uuidString, title: "New conversation", entryIntent: nil,
            client: client
        )
        let responseID = UUID().uuidString
        let save = Task { await model.saveFeedback(responseMessageID: responseID, direction: .helpful, factors: [.coverage], detail: nil) }
        while !(await events.values()).contains("save-start") { await Task.yield() }
        let remove = Task { await model.saveFeedback(responseMessageID: responseID, direction: nil, factors: [], detail: nil) }
        await Task.yield()
        let beforeRelease = await events.values()
        XCTAssertEqual(beforeRelease, ["save-start"])
        await gate.open()
        await save.value
        await remove.value
        let finalEvents = await events.values()
        XCTAssertEqual(finalEvents, ["save-start", "save-end", "remove"])
    }

    private func message(role: String, body: String) -> MessageRecord {
        MessageRecord(
            id: UUID().uuidString, conversationID: UUID().uuidString,
            role: role, body: body, createdAtMS: 1
        )
    }
}

final class ResponseFeedbackEditorStateTests: XCTestCase {
    func testSelectingNewDirectionPersistsRatingImmediately() {
        var state = ResponseFeedbackEditorState(feedback: nil)

        let mutation = state.begin(.helpful)

        XCTAssertEqual(mutation, .save(direction: .helpful, factors: [], detail: nil))
        XCTAssertEqual(state.direction, .helpful)
        XCTAssertEqual(state.draftFactors, [])
        XCTAssertEqual(state.draftDetail, "")
    }

    func testDismissingDraftRestoresLastCommittedReasonsAndDetail() {
        var state = ResponseFeedbackEditorState(feedback: ResponseFeedbackRecord(
            responseMessageID: UUID().uuidString,
            direction: .notHelpful,
            factors: [.relationalFit],
            detail: "Too formal",
            updatedAtMS: 1
        ))

        XCTAssertNil(state.begin(.notHelpful))
        state.toggle(.communicationClarity)
        state.draftDetail = "A different unsaved explanation"
        state.discardDraft()

        XCTAssertEqual(state.draftFactors, [.relationalFit])
        XCTAssertEqual(state.draftDetail, "Too formal")
    }

    func testSavingDraftCommitsReasonsAndNormalizedDetail() {
        var state = ResponseFeedbackEditorState(feedback: nil)
        _ = state.begin(.helpful)
        state.toggle(.coverage)
        state.draftDetail = "  This covered the decision well.  "

        let mutation = state.commit()

        XCTAssertEqual(
            mutation,
            .save(
                direction: .helpful,
                factors: [.coverage],
                detail: "This covered the decision well."
            )
        )
        state.draftDetail = "Unsaved"
        state.discardDraft()
        XCTAssertEqual(state.draftDetail, "This covered the decision well.")
    }

    func testRemovingRatingClearsCommittedAndDraftFeedback() {
        var state = ResponseFeedbackEditorState(feedback: ResponseFeedbackRecord(
            responseMessageID: UUID().uuidString,
            direction: .helpful,
            factors: [.coverage],
            detail: "Useful",
            updatedAtMS: 1
        ))

        XCTAssertEqual(state.remove(), .remove)
        XCTAssertNil(state.direction)
        XCTAssertEqual(state.draftFactors, [])
        XCTAssertEqual(state.draftDetail, "")
    }

    func testBlankDetailNormalizesToNil() {
        var state = ResponseFeedbackEditorState(feedback: nil)
        _ = state.begin(.helpful)
        state.draftDetail = "   \n  "

        XCTAssertEqual(state.commit(), .save(direction: .helpful, factors: [], detail: nil))
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

private actor EventRecorder {
    private var events: [String] = []
    func append(_ event: String) { events.append(event) }
    func values() -> [String] { events }
}

private actor ResponseActionCallSpy {
    private var counts: [String: Int] = [:]
    func record(_ id: String) -> Int {
        counts[id, default: 0] += 1
        return counts[id, default: 0]
    }
    func count(_ id: String) -> Int { counts[id, default: 0] }
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
    private var feedback: ResponseFeedbackRecord?
    private var removedFeedback: String?

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
            sendText: { _, available in await available() },
            retry: { [self] in await recordRetry() }, saveDraft: { [self] input in await save(input) },
            discardDraft: { [self] in await recordDraftDiscard() },
            discardEmptyConversation: { [self] in await recordConversationDiscard() },
            correctTranscript: { [self, correctionFails] _, _ in
                await recordCorrectionRequest()
                if correctionFails { throw ConversationFailure.retryable }
            },
            loadCaptureSnapshot: { [captureDisposition] in
                .init(activity: .recording, elapsedMilliseconds: 0, meter: .init(averagePower: -160, peakPower: -160), disposition: captureDisposition)
            },
            saveFeedback: { [self] value in await save(value) },
            removeFeedback: { [self] id, _ in await removeFeedback(id) }
        )
    }
    private func recordBegin() { beginVoiceCount += 1 }
    private func save(_ input: ConversationInput) { saved = input }
    private func save(_ value: ResponseFeedbackRecord) { feedback = value }
    private func removeFeedback(_ id: String) { removedFeedback = UUID(uuidString: id)?.uuidString ?? id }
    func count() -> Int { beginVoiceCount }
    func savedInput() -> ConversationInput? { saved }
    private func recordDraftDiscard() { discardedDraftCount += 1 }
    private func recordConversationDiscard() { discardedConversationCount += 1 }
    func discardCounts() -> [Int] { [discardedDraftCount, discardedConversationCount] }
    private func recordCorrectionRequest() { correctionRequestCount += 1 }
    private func recordRetry() { retryCount += 1 }
    func correctionRequestCounts() -> [Int] { [correctionRequestCount, retryCount] }
    func savedFeedback() -> ResponseFeedbackRecord? { feedback }
    func removedFeedbackID() -> String? { removedFeedback }
}
