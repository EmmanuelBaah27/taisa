import Foundation
import Observation
import TaisaAudio
import TaisaConversations
import TaisaStorage
import TaisaVoice

struct ConversationScreenClient: Sendable {
    var loadMessages: @Sendable () async throws -> [MessageRecord]
    var loadAssistantResponses: @Sendable () async throws -> [String: AssistantResponseRecord]
    var loadTitle: @Sendable () async throws -> String
    var beginVoice: @Sendable () async throws -> Void
    var pauseVoice: @Sendable () async throws -> Void
    var resumeVoice: @Sendable () async throws -> Void
    var retryPauseVoice: @Sendable () async throws -> Void
    var retryResumeVoice: @Sendable () async throws -> Void
    var sendVoice: @Sendable (@escaping @MainActor @Sendable () async -> Void) async throws -> Void
    var sendText: @Sendable (
        String, @escaping @MainActor @Sendable () async -> Void
    ) async throws -> Void
    var retry: @Sendable () async throws -> Void
    var saveDraft: @Sendable (ConversationInput) async throws -> Void
    var discardDraft: @Sendable () async throws -> Void
    var discardEmptyConversation: @Sendable () async throws -> Void
    var correctTranscript: @Sendable (String, String) async throws -> Void
    var loadCaptureSnapshot: @Sendable () async -> VoiceCaptureSnapshot
    var loadPartialCoaching: @Sendable () async -> String
    var recoveryEvents: @Sendable () async -> AsyncStream<Void>
    var saveFeedback: @Sendable (ResponseFeedbackRecord) async throws -> Void
    var removeFeedback: @Sendable (String, Int64) async throws -> Void
    var acceptProposal: @Sendable (String) async throws -> Void
    var dismissProposal: @Sendable (String) async throws -> Void

    init(
        loadMessages: @escaping @Sendable () async throws -> [MessageRecord] = { [] },
        loadAssistantResponses: @escaping @Sendable () async throws -> [String: AssistantResponseRecord] = { [:] },
        loadTitle: @escaping @Sendable () async throws -> String = { "New conversation" },
        beginVoice: @escaping @Sendable () async throws -> Void,
        pauseVoice: @escaping @Sendable () async throws -> Void,
        resumeVoice: @escaping @Sendable () async throws -> Void,
        retryPauseVoice: @escaping @Sendable () async throws -> Void = {},
        retryResumeVoice: @escaping @Sendable () async throws -> Void = {},
        sendVoice: @escaping @Sendable (@escaping @MainActor @Sendable () async -> Void) async throws -> Void,
        sendText: @escaping @Sendable (
            String, @escaping @MainActor @Sendable () async -> Void
        ) async throws -> Void,
        retry: @escaping @Sendable () async throws -> Void,
        saveDraft: @escaping @Sendable (ConversationInput) async throws -> Void,
        discardDraft: @escaping @Sendable () async throws -> Void,
        discardEmptyConversation: @escaping @Sendable () async throws -> Void = {},
        correctTranscript: @escaping @Sendable (String, String) async throws -> Void = { _, _ in },
        loadCaptureSnapshot: @escaping @Sendable () async -> VoiceCaptureSnapshot = {
            .init(activity: .prepared, elapsedMilliseconds: 0, meter: .init(averagePower: -160, peakPower: -160), disposition: .empty)
        },
        loadPartialCoaching: @escaping @Sendable () async -> String = { "" },
        recoveryEvents: @escaping @Sendable () async -> AsyncStream<Void> = { AsyncStream { $0.finish() } },
        saveFeedback: @escaping @Sendable (ResponseFeedbackRecord) async throws -> Void = { _ in },
        removeFeedback: @escaping @Sendable (String, Int64) async throws -> Void = { _, _ in },
        acceptProposal: @escaping @Sendable (String) async throws -> Void = { _ in },
        dismissProposal: @escaping @Sendable (String) async throws -> Void = { _ in }
    ) {
        self.loadMessages = loadMessages
        self.loadAssistantResponses = loadAssistantResponses
        self.loadTitle = loadTitle
        self.beginVoice = beginVoice
        self.pauseVoice = pauseVoice
        self.resumeVoice = resumeVoice
        self.retryPauseVoice = retryPauseVoice
        self.retryResumeVoice = retryResumeVoice
        self.sendVoice = sendVoice
        self.sendText = sendText
        self.retry = retry
        self.saveDraft = saveDraft
        self.discardDraft = discardDraft
        self.discardEmptyConversation = discardEmptyConversation
        self.correctTranscript = correctTranscript
        self.loadCaptureSnapshot = loadCaptureSnapshot
        self.loadPartialCoaching = loadPartialCoaching
        self.recoveryEvents = recoveryEvents
        self.saveFeedback = saveFeedback
        self.removeFeedback = removeFeedback
        self.acceptProposal = acceptProposal
        self.dismissProposal = dismissProposal
    }
}

@MainActor
@Observable
final class ConversationViewModel {
    struct ResponseActionFailure: Identifiable {
        let id: String
        let message: String
        let retry: @MainActor () async -> Void
    }
    enum FailureContext: Equatable {
        case transcription, request, beginRecording, microphonePermissionDenied, pauseRecording, resumeRecording
    }
    enum Confirmation: Equatable {
        case discardVoiceForKeyboard(returnTo: ComposerState)
        case discardRecording
        case discardShortOrKeepRecording
        case saveDiscardOrCancel
    }

    enum PagePhase: Equatable { case preparing, empty, shortCapture, sendable, paused, saved, text, durableProcessing, waiting, failure }

    let conversationID: String
    private(set) var title: String
    private(set) var composer: ComposerState
    private(set) var isClosing = false
    private(set) var messages: [MessageRecord] = []
    private(set) var assistantResponses: [String: AssistantResponseRecord] = [:]
    private(set) var confirmation: Confirmation?
    private(set) var capture: VoiceCaptureSnapshot = .init(
        activity: .prepared, elapsedMilliseconds: 0,
        meter: .init(averagePower: -160, peakPower: -160), disposition: .empty
    )
    private(set) var correctionMessageID: String?
    private(set) var correctionRegenerationMessageID: String?
    private(set) var correctionRegenerationFailureMessageID: String?
    private(set) var partialCoaching = ""
    private(set) var streamingFinalMessageID: String?
    private(set) var isResponseStreaming = false
    private(set) var pendingSentText: String?
    private(set) var failureContext: FailureContext = .request
    private(set) var responseActionFailures: [ResponseActionFailure] = []
    private(set) var showsMicrophoneUnavailable = false
    var responseActionFailure: ResponseActionFailure? { responseActionFailures.first }
    private var processingMessageIsDurable = true
    private var correctionOriginalText = ""
    private var submittedCorrectionText: String?
    var correctionText = ""
    var canSubmitCorrection: Bool {
        let trimmed = correctionText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let submittedCorrectionText { return trimmed == submittedCorrectionText }
        return correctionMessageID != nil && !trimmed.isEmpty && trimmed != correctionOriginalText
    }
    var text: String {
        didSet { if case .typing = composer { composer = .typing(text) } }
    }
    var latestUserTranscript: String? {
        messages.last(where: { $0.role == "user" })?.body
    }
    var pagePhase: PagePhase {
        switch composer {
        case .preparingVoice: .preparing
        case .recording:
            switch capture.disposition { case .empty: .empty; case .shortCapture: .shortCapture; case .sendable: .sendable; case .durableProcessing: .durableProcessing }
        case .paused: .paused
        case .savedVoiceDraft: .saved
        case .typing: .text
        case .transcribing, .coaching: .durableProcessing
        case .waitingForReply: .waiting
        case .failure: .failure
        }
    }

    @ObservationIgnored private let entryIntent: ConversationEntryIntent?
    @ObservationIgnored private let client: ConversationScreenClient
    @ObservationIgnored private let dismiss: @MainActor () -> Void
    @ObservationIgnored private var started = false
    private(set) var actionInFlight = false
    @ObservationIgnored private var voicePreparationExit: VoicePreparationExit?
    @ObservationIgnored private var recoveryObservation: Task<Void, Never>?

    private enum VoicePreparationExit { case discard, keyboard }

    var isCorrectionSubmitting: Bool { actionInFlight && correctionMessageID != nil }
    var isSendingText: Bool { pendingSentText != nil }
    var closeActionDisabled: Bool {
        if composer == .preparingVoice { return false }
        return actionInFlight && !(composer == .coaching && processingMessageIsDurable)
    }
    var isCorrectionDirty: Bool {
        correctionMessageID != nil && correctionText != correctionOriginalText
    }

    @ObservationIgnored private var feedbackRevisionMS: Int64 = 0
    @ObservationIgnored private var feedbackMutationTails: [String: Task<Void, Never>] = [:]

    deinit {
        recoveryObservation?.cancel()
        feedbackMutationTails.values.forEach { $0.cancel() }
    }

    init(
        conversationID: String,
        title: String,
        entryIntent: ConversationEntryIntent?,
        composer: ComposerState = .waitingForReply,
        text: String = "",
        client: ConversationScreenClient,
        dismiss: @escaping @MainActor () -> Void = {}
    ) {
        self.conversationID = conversationID
        self.title = title
        self.entryIntent = entryIntent
        self.composer = composer
        self.text = text
        self.client = client
        self.dismiss = dismiss
    }

    static func preview(
        composer: ComposerState,
        messages: [MessageRecord] = [],
        assistantResponses: [String: AssistantResponseRecord] = [:],
        dismiss: @escaping @MainActor () -> Void = {}
    ) -> ConversationViewModel {
        let model = ConversationViewModel(
            conversationID: "00000000-0000-0000-0000-000000000001",
            title: "New conversation",
            entryIntent: nil,
            composer: composer,
            text: { if case .typing(let value) = composer { value } else { "" } }(),
            client: ConversationScreenClient(
                loadMessages: { messages },
                loadAssistantResponses: { assistantResponses },
                beginVoice: {}, pauseVoice: {}, resumeVoice: {}, sendVoice: { _ in },
                sendText: { _, messageAvailable in await messageAvailable() },
                retry: {}, saveDraft: { _ in }, discardDraft: {}
            ),
            dismiss: dismiss
        )
        model.messages = messages
        model.assistantResponses = assistantResponses
        return model
    }

    static func overflowQAPreview() -> ConversationViewModel {
        let conversationID = "00000000-0000-0000-0000-000000000002"
        let messages = (1...18).map { index in
            MessageRecord(
                id: index == 18 ? "latest-message" : "overflow-message-\(index)",
                conversationID: conversationID,
                role: index.isMultiple(of: 2) ? "assistant" : "user",
                body: "Rendered conversation message \(index). This content makes the timeline overflow the visible screen.",
                createdAtMS: Int64(index)
            )
        }
        return ConversationViewModel(
            conversationID: conversationID,
            title: "Overflow conversation",
            entryIntent: nil,
            client: ConversationScreenClient(
                loadMessages: {
                    try? await Task.sleep(for: .milliseconds(100))
                    return messages
                },
                beginVoice: {}, pauseVoice: {}, resumeVoice: {}, sendVoice: { _ in },
                sendText: { _, messageAvailable in await messageAvailable() },
                retry: {}, saveDraft: { _ in }, discardDraft: {}
            )
        )
    }

    func start() async {
        guard !started else { return }
        started = true
        let recoveryEvents = client.recoveryEvents
        recoveryObservation = Task { [weak self] in
            let events = await recoveryEvents()
            for await _ in events {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                await reloadMessages()
                capture = await client.loadCaptureSnapshot()
                if composer == .failure(.retryable) || composer == .coaching || composer == .transcribing {
                    finishResponseIfPersisted()
                }
            }
        }
        do {
            messages = try await client.loadMessages()
            if let loadedTitle = try? await client.loadTitle() { title = loadedTitle }
            capture = await client.loadCaptureSnapshot()
            assistantResponses = try await client.loadAssistantResponses()
            switch entryIntent {
            case .voice: try await beginVoice()
            case .text: composer = .typing(""); text = ""
            case nil: break
            }
        } catch {
            composer = .failure(.unavailable)
        }
    }

    func beginVoice() async throws {
        guard !actionInFlight else { return }
        actionInFlight = true
        composer = .preparingVoice
        do {
            try await client.beginVoice()
            actionInFlight = false
            if await completeVoicePreparationExitIfNeeded() { return }
            composer = .recording
            await refreshCapture()
        }
        catch {
            actionInFlight = false
            if await completeVoicePreparationExitIfNeeded() { return }
            print("TAISA_CAPTURE begin.failure type=\(String(reflecting: type(of: error)))")
            failureContext = error as? AudioCaptureError == .permissionDenied
                ? .microphonePermissionDenied
                : .beginRecording
            composer = .failure(.unavailable)
            throw error
        }
    }

    private func completeVoicePreparationExitIfNeeded() async -> Bool {
        guard let exit = voicePreparationExit else { return false }
        voicePreparationExit = nil
        switch exit {
        case .discard: await discardRecordingAndRemainOrDismiss()
        case .keyboard: confirmKeyboardReplacement()
        }
        return true
    }

    func pause() async { await perform(next: .paused, recovery: .pauseRecording) { try await client.pauseVoice() }; await refreshCapture() }
    func resume() async {
        guard !actionInFlight else { return }
        actionInFlight = true
        do {
            try await client.resumeVoice()
            composer = .recording
            showsMicrophoneUnavailable = false
        } catch {
            capture = await client.loadCaptureSnapshot()
            if capture.interruption == .microphoneUnavailable {
                composer = .paused
                showsMicrophoneUnavailable = true
            } else {
                failureContext = .resumeRecording
                composer = .failure(.retryable)
            }
        }
        actionInFlight = false
        await refreshCapture()
    }
    func refreshCapture() async {
        let wasUnavailable = capture.interruption == .microphoneUnavailable
        capture = await client.loadCaptureSnapshot()
        if capture.interruption == .microphoneUnavailable, !wasUnavailable {
            showsMicrophoneUnavailable = true
        } else if capture.interruption == nil {
            showsMicrophoneUnavailable = false
        }
        switch capture.activity {
        case .recording:
            if composer == .preparingVoice || composer == .paused { composer = .recording }
        case .paused, .blocked:
            if composer == .preparingVoice || composer == .recording { composer = .paused }
        case .finalized:
            if composer == .preparingVoice || composer == .recording || composer == .paused { composer = .savedVoiceDraft }
        case .prepared, .cancelled, .discarded:
            break
        }
    }

    func dismissMicrophoneUnavailable() { showsMicrophoneUnavailable = false }

    func refreshPartialCoaching() async {
        let latestPartial = await client.loadPartialCoaching()
        guard !Task.isCancelled, composer == .coaching else { return }
        await reloadMessages()
        guard !Task.isCancelled, composer == .coaching else { return }
        if let finalAssistant = latestAssistantAfterLatestUser() {
            partialCoaching = latestPartial.isEmpty ? finalAssistant.body : latestPartial
            streamingFinalMessageID = finalAssistant.id
        } else {
            partialCoaching = latestPartial
        }
    }

    func requestDiscardRecording() {
        if composer == .preparingVoice, actionInFlight {
            voicePreparationExit = .discard
            return
        }
        if capture.disposition == .empty {
            Task { @MainActor in await discardRecordingAndRemainOrDismiss() }
        } else {
            confirmation = .discardRecording
        }
    }

    func confirmDiscardRecording() async { await discardRecordingAndRemainOrDismiss() }
    func sendVoice() async {
        guard !actionInFlight else { return }
        actionInFlight = true
        partialCoaching = ""
        composer = .transcribing
        var transcriptBecameAvailable = false
        do {
            try await client.sendVoice { [weak self] in
                guard let self else { return }
                transcriptBecameAvailable = true
                await self.reloadMessages()
                self.composer = .coaching
                self.isResponseStreaming = true
            }
            await prepareCompletedStreamPresentation()
        } catch {
            isResponseStreaming = false
            partialCoaching = ""
            streamingFinalMessageID = nil
            failureContext = transcriptBecameAvailable ? .request : .transcription
            composer = .failure(.retryable)
        }
        actionInFlight = false
    }

    func sendText() async {
        guard !actionInFlight else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        actionInFlight = true
        partialCoaching = ""
        pendingSentText = value
        let messageIDsBeforeSend = Set(messages.map(\.id))
        processingMessageIsDurable = false
        composer = .coaching
        isResponseStreaming = true
        do {
            try await client.sendText(value) { [weak self] in
                guard let self else { return }
                await self.reloadMessages()
                self.processingMessageIsDurable = true
                if self.messages.contains(where: {
                    $0.role == "user" && $0.body == value && !messageIDsBeforeSend.contains($0.id)
                }) {
                    self.text = ""
                    await Task.yield()
                }
            }
            await prepareCompletedStreamPresentation()
            pendingSentText = nil
        }
        catch {
            isResponseStreaming = false
            partialCoaching = ""
            streamingFinalMessageID = nil
            pendingSentText = nil
            await reloadMessages()
            failureContext = .request
            if messages.contains(where: {
                $0.role == "user" && $0.body == value && !messageIDsBeforeSend.contains($0.id)
            }) {
                processingMessageIsDurable = true
                text = ""
                composer = .failure(.retryable)
            } else {
                processingMessageIsDurable = true
                text = value
                composer = .typing(value)
            }
        }
        actionInFlight = false
    }

    func completeStreamingPresentation() {
        guard streamingFinalMessageID != nil else { return }
        streamingFinalMessageID = nil
        partialCoaching = ""
        finishResponseIfPersisted()
    }

    func retry() async {
        guard !actionInFlight else { return }
        switch failureContext {
        case .transcription:
            partialCoaching = ""
            composer = .transcribing
            await performSuccess { try await client.retry() }
        case .beginRecording:
            try? await beginVoice()
        case .microphonePermissionDenied:
            break
        case .pauseRecording:
            await perform(next: .paused, recovery: .pauseRecording) { try await client.retryPauseVoice() }
            await refreshCapture()
        case .resumeRecording:
            await perform(next: .recording, recovery: .resumeRecording) { try await client.retryResumeVoice() }
            await refreshCapture()
        case .request:
            partialCoaching = ""
            composer = .coaching
            await performSuccess { try await client.retry() }
            partialCoaching = ""
            if composer == .waitingForReply, correctionRegenerationMessageID != nil {
                correctionRegenerationMessageID = nil
                submittedCorrectionText = nil
            }
        }
    }

    func requestKeyboard() {
        if composer == .preparingVoice, actionInFlight {
            voicePreparationExit = .keyboard
            return
        }
        switch composer {
        case .recording, .paused, .preparingVoice:
            if capture.disposition == .empty {
                confirmKeyboardReplacement()
            } else {
                confirmation = .discardVoiceForKeyboard(returnTo: composer)
            }
        case .savedVoiceDraft:
            break
        case .waitingForReply:
            composer = .typing("")
        default:
            break
        }
    }

    func confirmKeyboardReplacement() {
        guard !actionInFlight else { return }
        actionInFlight = true
        text = ""
        composer = .typing("")
        confirmation = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await client.discardDraft() }
            catch { composer = .failure(.unavailable) }
            actionInFlight = false
        }
    }

    func requestClose() {
        if composer == .preparingVoice, actionInFlight {
            voicePreparationExit = .discard
            return
        }
        guard !closeActionDisabled else { return }
        if capture.disposition == .empty {
            switch composer {
            case .preparingVoice, .recording, .paused:
                Task { @MainActor in await discardRecordingAndRemainOrDismiss() }
                return
            default:
                break
            }
        }
        if capture.disposition == .shortCapture {
            switch composer {
            case .recording, .paused:
                confirmation = .discardShortOrKeepRecording
                return
            default:
                break
            }
        }
        switch composer {
        case .transcribing:
            closeConversation()
        case .coaching:
            if processingMessageIsDurable { closeConversation() }
        case .failure:
            if hasRecoverableFailurePayload {
                confirmation = .saveDiscardOrCancel
            } else {
                cancelRecoveryAndClose()
            }
        case .preparingVoice, .recording, .paused, .savedVoiceDraft:
            confirmation = .saveDiscardOrCancel
        case .typing where hasUnsentInput:
            confirmation = .saveDiscardOrCancel
        case .typing where messages.isEmpty:
            Task { @MainActor in
                guard !self.actionInFlight else { return }
                self.actionInFlight = true
                defer { self.actionInFlight = false }
                do {
                    try await client.discardEmptyConversation()
                    closeConversation()
                } catch {
                    isClosing = false
                    composer = .failure(.unavailable)
                }
            }
        case .waitingForReply where messages.isEmpty:
            Task { @MainActor in
                guard !self.actionInFlight else { return }
                self.actionInFlight = true
                defer { self.actionInFlight = false }
                do {
                    try await client.discardEmptyConversation()
                    closeConversation()
                } catch {
                    isClosing = false
                    composer = .failure(.unavailable)
                }
            }
        default:
            closeConversation()
        }
    }

    func cancelRecoveryAndClose() { closeConversation() }

    func continueWithKeyboardAfterPermissionDenial() {
        guard failureContext == .microphonePermissionDenied else { return }
        text = ""
        composer = .typing("")
    }

    func continueWithKeyboardAfterRecordingFailure() {
        guard failureContext == .beginRecording else { return }
        text = ""
        composer = .typing("")
    }

    func cancelConfirmation() {
        guard !actionInFlight else { return }
        if case .discardVoiceForKeyboard(let prior) = confirmation { composer = prior }
        confirmation = nil
    }

    private func discardRecordingAndRemainOrDismiss() async {
        guard !actionInFlight else { return }
        actionInFlight = true
        confirmation = nil
        let closesEmptyConversation = messages.isEmpty
        if closesEmptyConversation { isClosing = true }
        do {
            try await client.discardDraft()
            if closesEmptyConversation {
                try await client.discardEmptyConversation()
                closeConversation()
            } else {
                composer = .waitingForReply
            }
        } catch {
            isClosing = false
            composer = .failure(.unavailable)
            confirmation = nil
        }
        actionInFlight = false
    }

    func saveAndClose() async {
        guard !actionInFlight else { return }
        actionInFlight = true
        isClosing = true
        defer { actionInFlight = false }
        do {
            let input: ConversationInput = {
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .text(text) }
                if case .typing = composer { return .text(text) }
                return .voice
            }()
            try await client.saveDraft(input)
            confirmation = nil
            closeConversation()
        } catch {
            isClosing = false
            composer = .failure(.unavailable)
            confirmation = nil
        }
    }

    func discardAndClose() async {
        guard !actionInFlight else { return }
        actionInFlight = true
        isClosing = true
        defer { actionInFlight = false }
        do {
            try await client.discardDraft()
            if messages.isEmpty { try await client.discardEmptyConversation() }
            confirmation = nil
            closeConversation()
        }
        catch {
            isClosing = false
            composer = .failure(.unavailable)
            confirmation = nil
        }
    }

    private func closeConversation() {
        isClosing = true
        dismiss()
    }

    func requestCorrection(_ message: MessageRecord) {
        guard !actionInFlight, message.role == "user", correctionMessageID == nil,
              correctionRegenerationMessageID == nil else { return }
        correctionMessageID = message.id
        correctionText = message.body
        correctionOriginalText = message.body
    }

    func cancelCorrection() {
        correctionMessageID = nil
        correctionText = ""
        correctionOriginalText = ""
        if correctionRegenerationMessageID == nil { submittedCorrectionText = nil }
    }

    func submitCorrection() async {
        guard !actionInFlight, let messageID = correctionMessageID, canSubmitCorrection,
              let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        actionInFlight = true
        defer { actionInFlight = false }
        let correctedText = correctionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isRetryingPreservedRequest = correctionRegenerationMessageID == messageID
        if !isRetryingPreservedRequest {
            let original = messages[index]
            messages[index] = MessageRecord(
                id: original.id, conversationID: original.conversationID,
                role: original.role, body: correctedText, createdAtMS: original.createdAtMS
            )
            correctionRegenerationMessageID = messageID
            submittedCorrectionText = correctedText
        }
        composer = .coaching
        partialCoaching = ""
        do {
            if isRetryingPreservedRequest {
                try await client.retry()
            } else {
                try await client.correctTranscript(messageID, correctedText)
            }
            await reloadMessages()
            partialCoaching = ""
            correctionRegenerationMessageID = nil
            correctionRegenerationFailureMessageID = nil
            submittedCorrectionText = nil
            cancelCorrection()
            composer = .waitingForReply
        } catch {
            partialCoaching = ""
            await reloadMessages()
            if messages.contains(where: { $0.id == messageID && $0.body == correctedText }) {
                correctionMessageID = nil
                correctionText = ""
                correctionOriginalText = ""
                correctionRegenerationFailureMessageID = messageID
                composer = .waitingForReply
            } else {
                if let reloadedIndex = messages.firstIndex(where: { $0.id == messageID }) {
                    let original = messages[reloadedIndex]
                    messages[reloadedIndex] = MessageRecord(
                        id: original.id, conversationID: original.conversationID,
                        role: original.role, body: correctedText, createdAtMS: original.createdAtMS
                    )
                }
                composer = .failure(.retryable)
            }
        }
    }

    func retryCorrectionRegeneration() async {
        guard !actionInFlight, let messageID = correctionRegenerationFailureMessageID else { return }
        actionInFlight = true
        correctionRegenerationFailureMessageID = nil
        composer = .coaching
        defer { actionInFlight = false }
        do {
            try await client.retry()
            await reloadMessages()
            correctionRegenerationMessageID = nil
            submittedCorrectionText = nil
            composer = .waitingForReply
        } catch {
            correctionRegenerationFailureMessageID = messageID
            composer = .waitingForReply
        }
    }

    func keepEditedMessage() {
        correctionRegenerationFailureMessageID = nil
        correctionRegenerationMessageID = nil
        submittedCorrectionText = nil
        composer = .waitingForReply
    }

    func saveFeedback(
        responseMessageID: String,
        direction: ResponseFeedbackDirection?,
        factors: [ResponseQualityFactor],
        detail: String?
    ) async {
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        feedbackRevisionMS = max(now, feedbackRevisionMS + 1)
        let revision = feedbackRevisionMS
        let previous = feedbackMutationTails[responseMessageID]
        let task = Task { @MainActor in
            await previous?.value
            do {
                if let direction {
                    try await client.saveFeedback(.init(
                        responseMessageID: responseMessageID, direction: direction,
                        factors: factors, detail: detail, updatedAtMS: revision
                    ))
                } else {
                    try await client.removeFeedback(responseMessageID, revision)
                }
                removeResponseActionFailure(id: "feedback:\(responseMessageID)")
                await reloadMessages()
            } catch {
                await reloadMessages()
                enqueueResponseActionFailure(
                    id: "feedback:\(responseMessageID)",
                    message: "Couldn’t save feedback. Try again."
                ) { [weak self] in
                    await self?.saveFeedback(
                        responseMessageID: responseMessageID, direction: direction,
                        factors: factors, detail: detail
                    )
                }
            }
        }
        feedbackMutationTails[responseMessageID] = task
        await task.value
    }

    func acceptProposal(_ id: String) async {
        do { try await client.acceptProposal(id); removeResponseActionFailure(id: "accept:\(id)"); await reloadMessages() }
        catch {
            await reloadMessages()
            enqueueResponseActionFailure(id: "accept:\(id)", message: "Couldn’t add this suggestion. Try again.") { [weak self] in
                await self?.acceptProposal(id)
            }
        }
    }

    func dismissProposal(_ id: String) async {
        do { try await client.dismissProposal(id); removeResponseActionFailure(id: "dismiss:\(id)"); await reloadMessages() }
        catch {
            await reloadMessages()
            enqueueResponseActionFailure(id: "dismiss:\(id)", message: "Couldn’t dismiss this suggestion. Try again.") { [weak self] in
                await self?.dismissProposal(id)
            }
        }
    }

    func retryFailedResponseAction() async { await responseActionFailure?.retry() }

    func clearResponseActionFailure() {
        guard !responseActionFailures.isEmpty else { return }
        responseActionFailures.removeFirst()
    }

    private func enqueueResponseActionFailure(
        id: String, message: String, retry: @escaping @MainActor () async -> Void
    ) {
        responseActionFailures.removeAll { $0.id == id }
        responseActionFailures.append(.init(id: id, message: message, retry: retry))
    }

    private func removeResponseActionFailure(id: String) {
        responseActionFailures.removeAll { $0.id == id }
    }

    private var hasUnsentInput: Bool {
        switch composer {
        case .typing: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .preparingVoice, .recording, .paused, .savedVoiceDraft, .transcribing, .coaching, .failure: true
        case .waitingForReply: false
        }
    }

    private var hasRecoverableFailurePayload: Bool {
        !messages.isEmpty
            || capture.disposition != .empty
            || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func perform(
        next: ComposerState,
        recovery: FailureContext = .request,
        operation: () async throws -> Void
    ) async {
        guard !actionInFlight else { return }
        actionInFlight = true
        do { try await operation(); composer = next }
        catch { failureContext = recovery; composer = .failure(.retryable) }
        actionInFlight = false
    }

    private func performSuccess(operation: () async throws -> Void) async {
        guard !actionInFlight else { return }
        actionInFlight = true
        do {
            try await operation()
            await reloadMessages()
            finishResponseIfPersisted()
        } catch {
            composer = .failure(.retryable)
        }
        actionInFlight = false
    }

    private func reloadMessages() async {
        if let loaded = try? await client.loadMessages() { messages = loaded }
        if let loaded = try? await client.loadAssistantResponses() { assistantResponses = loaded }
        if let loadedTitle = try? await client.loadTitle() { title = loadedTitle }
    }

    private func prepareCompletedStreamPresentation() async {
        isResponseStreaming = false
        let finalPartial = await client.loadPartialCoaching()
        await reloadMessages()
        let finalAssistant = latestAssistantAfterLatestUser()
        guard let finalAssistant else {
            partialCoaching = ""
            streamingFinalMessageID = nil
            finishResponseIfPersisted()
            return
        }
        partialCoaching = finalPartial.isEmpty ? finalAssistant.body : finalPartial
        streamingFinalMessageID = finalAssistant.id
        composer = .coaching
    }

    private func latestAssistantAfterLatestUser() -> MessageRecord? {
        guard let latestUserIndex = messages.lastIndex(where: { $0.role == "user" }) else {
            return messages.last(where: { $0.role == "assistant" })
        }
        return messages[messages.index(after: latestUserIndex)...]
            .last(where: { $0.role == "assistant" })
    }

    private func finishResponseIfPersisted() {
        let hasAssistantReply: Bool
        if let latestUserIndex = messages.lastIndex(where: { $0.role == "user" }) {
            hasAssistantReply = messages[messages.index(after: latestUserIndex)...]
                .contains(where: { $0.role == "assistant" })
        } else {
            hasAssistantReply = messages.contains(where: { $0.role == "assistant" })
        }

        if hasAssistantReply {
            composer = .waitingForReply
        } else {
            failureContext = .request
            composer = .failure(.retryable)
        }
    }
}
