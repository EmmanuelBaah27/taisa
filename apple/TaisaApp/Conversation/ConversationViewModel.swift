import Observation
import TaisaConversations
import TaisaStorage
import TaisaVoice

struct ConversationScreenClient: Sendable {
    var loadMessages: @Sendable () async throws -> [MessageRecord]
    var loadTitle: @Sendable () async throws -> String
    var beginVoice: @Sendable () async throws -> Void
    var pauseVoice: @Sendable () async throws -> Void
    var resumeVoice: @Sendable () async throws -> Void
    var sendVoice: @Sendable (@escaping @MainActor @Sendable () async -> Void) async throws -> Void
    var sendText: @Sendable (String) async throws -> Void
    var retry: @Sendable () async throws -> Void
    var saveDraft: @Sendable (ConversationInput) async throws -> Void
    var discardDraft: @Sendable () async throws -> Void
    var discardEmptyConversation: @Sendable () async throws -> Void
    var correctTranscript: @Sendable (String, String) async throws -> Void
    var loadCaptureSnapshot: @Sendable () async -> VoiceCaptureSnapshot
    var loadPartialCoaching: @Sendable () async -> String
    var recoveryEvents: @Sendable () async -> AsyncStream<Void>

    init(
        loadMessages: @escaping @Sendable () async throws -> [MessageRecord] = { [] },
        loadTitle: @escaping @Sendable () async throws -> String = { "New conversation" },
        beginVoice: @escaping @Sendable () async throws -> Void,
        pauseVoice: @escaping @Sendable () async throws -> Void,
        resumeVoice: @escaping @Sendable () async throws -> Void,
        sendVoice: @escaping @Sendable (@escaping @MainActor @Sendable () async -> Void) async throws -> Void,
        sendText: @escaping @Sendable (String) async throws -> Void,
        retry: @escaping @Sendable () async throws -> Void,
        saveDraft: @escaping @Sendable (ConversationInput) async throws -> Void,
        discardDraft: @escaping @Sendable () async throws -> Void,
        discardEmptyConversation: @escaping @Sendable () async throws -> Void = {},
        correctTranscript: @escaping @Sendable (String, String) async throws -> Void = { _, _ in },
        loadCaptureSnapshot: @escaping @Sendable () async -> VoiceCaptureSnapshot = {
            .init(activity: .prepared, elapsedMilliseconds: 0, meter: .init(averagePower: -160, peakPower: -160), disposition: .empty)
        },
        loadPartialCoaching: @escaping @Sendable () async -> String = { "" },
        recoveryEvents: @escaping @Sendable () async -> AsyncStream<Void> = { AsyncStream { $0.finish() } }
    ) {
        self.loadMessages = loadMessages
        self.loadTitle = loadTitle
        self.beginVoice = beginVoice
        self.pauseVoice = pauseVoice
        self.resumeVoice = resumeVoice
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
    }
}

@MainActor
@Observable
final class ConversationViewModel {
    private enum FailureRecovery { case request, beginVoice, pauseVoice, resumeVoice }
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
    private(set) var messages: [MessageRecord] = []
    private(set) var confirmation: Confirmation?
    private(set) var capture: VoiceCaptureSnapshot = .init(
        activity: .prepared, elapsedMilliseconds: 0,
        meter: .init(averagePower: -160, peakPower: -160), disposition: .empty
    )
    private(set) var correctionMessageID: String?
    private(set) var correctionRegenerationMessageID: String?
    private(set) var partialCoaching = ""
    private var correctionOriginalText = ""
    var correctionText = ""
    var canSubmitCorrection: Bool {
        let trimmed = correctionText.trimmingCharacters(in: .whitespacesAndNewlines)
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
    @ObservationIgnored private var actionInFlight = false
    @ObservationIgnored private var failureRecovery: FailureRecovery = .request
    @ObservationIgnored private var recoveryObservation: Task<Void, Never>?

    deinit { recoveryObservation?.cancel() }

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
                beginVoice: {}, pauseVoice: {}, resumeVoice: {}, sendVoice: { _ in },
                sendText: { _ in }, retry: {}, saveDraft: { _ in }, discardDraft: {}
            ),
            dismiss: dismiss
        )
        model.messages = messages
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
        return preview(composer: .waitingForReply, messages: messages)
    }

    func start() async {
        guard !started else { return }
        started = true
        recoveryObservation = Task { [weak self] in
            guard let self else { return }
            let events = await client.recoveryEvents()
            for await _ in events {
                guard !Task.isCancelled else { return }
                await reloadMessages()
                capture = await client.loadCaptureSnapshot()
                composer = .waitingForReply
            }
        }
        do {
            messages = try await client.loadMessages()
            capture = await client.loadCaptureSnapshot()
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
        defer { actionInFlight = false }
        composer = .preparingVoice
        do { try await client.beginVoice(); composer = .recording; await refreshCapture() }
        catch { failureRecovery = .beginVoice; composer = .failure(.unavailable); throw error }
    }

    func pause() async { await perform(next: .paused, recovery: .pauseVoice) { try await client.pauseVoice() }; await refreshCapture() }
    func resume() async { await perform(next: .recording, recovery: .resumeVoice) { try await client.resumeVoice() }; await refreshCapture() }
    func refreshCapture() async {
        capture = await client.loadCaptureSnapshot()
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

    func refreshPartialCoaching() async {
        partialCoaching = await client.loadPartialCoaching()
    }

    func requestDiscardRecording() {
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
        composer = .transcribing
        do {
            try await client.sendVoice { [weak self] in
                guard let self else { return }
                await self.reloadMessages()
                self.composer = .coaching
            }
            await reloadMessages()
            composer = .waitingForReply
        } catch {
            failureRecovery = .request
            composer = .failure(.retryable)
        }
        actionInFlight = false
    }

    func sendText() async {
        guard !actionInFlight else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        actionInFlight = true
        composer = .coaching
        do { try await client.sendText(value); text = ""; composer = .waitingForReply; await reloadMessages() }
        catch { failureRecovery = .request; composer = .failure(.retryable) }
        actionInFlight = false
    }

    func retry() async {
        guard !actionInFlight else { return }
        switch failureRecovery {
        case .beginVoice:
            try? await beginVoice()
        case .pauseVoice:
            await pause()
        case .resumeVoice:
            await resume()
        case .request:
            composer = .coaching
            await performSuccess { try await client.retry() }
        }
    }

    func requestKeyboard() {
        switch composer {
        case .recording, .paused, .preparingVoice:
            if capture.disposition == .empty {
                Task { @MainActor in await discardVoiceAndType() }
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

    func confirmKeyboardReplacement() async {
        guard case .discardVoiceForKeyboard = confirmation else { return }
        await discardVoiceAndType()
    }

    private func discardVoiceAndType() async {
        guard !actionInFlight else { return }
        actionInFlight = true
        defer { actionInFlight = false }
        do { try await client.discardDraft(); text = ""; composer = .typing(""); confirmation = nil }
        catch { composer = .failure(.unavailable); confirmation = nil }
    }

    func requestClose() {
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
        case .transcribing, .coaching:
            dismiss()
        case .failure:
            cancelRecoveryAndClose()
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
                    dismiss()
                } catch {
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
                    dismiss()
                } catch {
                    composer = .failure(.unavailable)
                }
            }
        default:
            dismiss()
        }
    }

    func cancelRecoveryAndClose() { dismiss() }

    func cancelConfirmation() {
        if case .discardVoiceForKeyboard(let prior) = confirmation { composer = prior }
        confirmation = nil
    }

    private func discardRecordingAndRemainOrDismiss() async {
        guard !actionInFlight else { return }
        actionInFlight = true
        do {
            try await client.discardDraft()
            confirmation = nil
            if messages.isEmpty {
                try await client.discardEmptyConversation(); dismiss()
            } else {
                composer = .waitingForReply
            }
        } catch { composer = .failure(.unavailable); confirmation = nil }
        actionInFlight = false
    }

    func saveAndClose() async {
        guard !actionInFlight else { return }
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            let input: ConversationInput = {
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .text(text) }
                if case .typing = composer { return .text(text) }
                return .voice
            }()
            try await client.saveDraft(input)
            confirmation = nil
            dismiss()
        } catch { composer = .failure(.unavailable); confirmation = nil }
    }

    func discardAndClose() async {
        guard !actionInFlight else { return }
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            try await client.discardDraft()
            if messages.isEmpty { try await client.discardEmptyConversation() }
            confirmation = nil
            dismiss()
        }
        catch { composer = .failure(.unavailable); confirmation = nil }
    }

    func requestCorrection(_ message: MessageRecord) {
        guard !actionInFlight, message.role == "user", correctionMessageID == nil else { return }
        correctionMessageID = message.id
        correctionText = message.body
        correctionOriginalText = message.body
    }

    func cancelCorrection() {
        correctionMessageID = nil
        correctionText = ""
        correctionOriginalText = ""
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
        }
        composer = .coaching
        do {
            if isRetryingPreservedRequest {
                try await client.retry()
            } else {
                try await client.correctTranscript(messageID, correctedText)
            }
            cancelCorrection()
            await reloadMessages()
            correctionRegenerationMessageID = nil
            composer = .waitingForReply
        } catch {
            composer = .failure(.retryable)
        }
    }

    private var hasUnsentInput: Bool {
        switch composer {
        case .typing: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .preparingVoice, .recording, .paused, .savedVoiceDraft, .transcribing, .coaching, .failure: true
        case .waitingForReply: false
        }
    }

    private func perform(
        next: ComposerState,
        recovery: FailureRecovery = .request,
        operation: () async throws -> Void
    ) async {
        guard !actionInFlight else { return }
        actionInFlight = true
        do { try await operation(); composer = next }
        catch { failureRecovery = recovery; composer = .failure(.retryable) }
        actionInFlight = false
    }

    private func performSuccess(operation: () async throws -> Void) async {
        guard !actionInFlight else { return }
        actionInFlight = true
        do {
            try await operation()
            await reloadMessages()
            composer = .waitingForReply
        } catch {
            composer = .failure(.retryable)
        }
        actionInFlight = false
    }

    private func reloadMessages() async {
        if let loaded = try? await client.loadMessages() { messages = loaded }
        if let loadedTitle = try? await client.loadTitle() { title = loadedTitle }
    }
}
