import Observation
import TaisaConversations
import TaisaStorage

struct ConversationScreenClient: Sendable {
    var loadMessages: @Sendable () async throws -> [MessageRecord]
    var beginVoice: @Sendable () async throws -> Void
    var pauseVoice: @Sendable () async throws -> Void
    var resumeVoice: @Sendable () async throws -> Void
    var sendVoice: @Sendable () async throws -> Void
    var sendText: @Sendable (String) async throws -> Void
    var retry: @Sendable () async throws -> Void
    var saveDraft: @Sendable (ConversationInput) async throws -> Void
    var discardDraft: @Sendable () async throws -> Void
    var correctTranscript: @Sendable (String, String) async throws -> Void

    init(
        loadMessages: @escaping @Sendable () async throws -> [MessageRecord] = { [] },
        beginVoice: @escaping @Sendable () async throws -> Void,
        pauseVoice: @escaping @Sendable () async throws -> Void,
        resumeVoice: @escaping @Sendable () async throws -> Void,
        sendVoice: @escaping @Sendable () async throws -> Void,
        sendText: @escaping @Sendable (String) async throws -> Void,
        retry: @escaping @Sendable () async throws -> Void,
        saveDraft: @escaping @Sendable (ConversationInput) async throws -> Void,
        discardDraft: @escaping @Sendable () async throws -> Void,
        correctTranscript: @escaping @Sendable (String, String) async throws -> Void = { _, _ in }
    ) {
        self.loadMessages = loadMessages
        self.beginVoice = beginVoice
        self.pauseVoice = pauseVoice
        self.resumeVoice = resumeVoice
        self.sendVoice = sendVoice
        self.sendText = sendText
        self.retry = retry
        self.saveDraft = saveDraft
        self.discardDraft = discardDraft
        self.correctTranscript = correctTranscript
    }
}

@MainActor
@Observable
final class ConversationViewModel {
    enum Confirmation: Equatable {
        case discardVoiceForKeyboard(returnTo: ComposerState)
        case saveDiscardOrCancel
    }

    let conversationID: String
    private(set) var title: String
    private(set) var composer: ComposerState
    private(set) var messages: [MessageRecord] = []
    private(set) var confirmation: Confirmation?
    private(set) var correctionMessageID: String?
    var correctionText = ""
    var text: String {
        didSet { if case .typing = composer { composer = .typing(text) } }
    }

    @ObservationIgnored private let entryIntent: ConversationEntryIntent?
    @ObservationIgnored private let client: ConversationScreenClient
    @ObservationIgnored private let dismiss: @MainActor () -> Void
    @ObservationIgnored private var started = false
    @ObservationIgnored private var actionInFlight = false

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
                beginVoice: {}, pauseVoice: {}, resumeVoice: {}, sendVoice: {},
                sendText: { _ in }, retry: {}, saveDraft: { _ in }, discardDraft: {}
            ),
            dismiss: dismiss
        )
        model.messages = messages
        return model
    }

    func start() async {
        guard !started else { return }
        started = true
        do {
            messages = try await client.loadMessages()
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
        composer = .preparingVoice
        do { try await client.beginVoice(); composer = .recording }
        catch { composer = .failure(.unavailable); throw error }
    }

    func pause() async { await perform(next: .paused) { try await client.pauseVoice() } }
    func resume() async { await perform(next: .recording) { try await client.resumeVoice() } }
    func sendVoice() async { await perform(next: .transcribing) { try await client.sendVoice() } }

    func sendText() async {
        guard !actionInFlight else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        actionInFlight = true
        composer = .coaching
        do { try await client.sendText(value); text = ""; composer = .waitingForReply; await reloadMessages() }
        catch { composer = .failure(.retryable) }
        actionInFlight = false
    }

    func retry() async { await perform(next: .coaching) { try await client.retry() } }

    func requestKeyboard() {
        switch composer {
        case .recording, .paused, .preparingVoice:
            confirmation = .discardVoiceForKeyboard(returnTo: composer)
        case .waitingForReply:
            composer = .typing("")
        default:
            break
        }
    }

    func confirmKeyboardReplacement() async {
        guard case .discardVoiceForKeyboard = confirmation else { return }
        do { try await client.discardDraft(); text = ""; composer = .typing(""); confirmation = nil }
        catch { composer = .failure(.unavailable); confirmation = nil }
    }

    func requestClose() {
        if hasUnsentInput { confirmation = .saveDiscardOrCancel } else { dismiss() }
    }

    func cancelConfirmation() {
        if case .discardVoiceForKeyboard(let prior) = confirmation { composer = prior }
        confirmation = nil
    }

    func saveAndClose() async {
        do {
            let input: ConversationInput = {
                if case .typing = composer { return .text(text) }
                return .voice
            }()
            try await client.saveDraft(input)
            confirmation = nil
            dismiss()
        } catch { composer = .failure(.unavailable); confirmation = nil }
    }

    func discardAndClose() async {
        do { try await client.discardDraft(); confirmation = nil; dismiss() }
        catch { composer = .failure(.unavailable); confirmation = nil }
    }

    func requestCorrection(_ message: MessageRecord) {
        correctionMessageID = message.id
        correctionText = message.body
    }

    func cancelCorrection() {
        correctionMessageID = nil
        correctionText = ""
    }

    func submitCorrection() async {
        guard let messageID = correctionMessageID else { return }
        composer = .coaching
        do {
            try await client.correctTranscript(messageID, correctionText)
            cancelCorrection()
            await reloadMessages()
            composer = .waitingForReply
        } catch {
            cancelCorrection()
            composer = .failure(.retryable)
        }
    }

    private var hasUnsentInput: Bool {
        switch composer {
        case .typing: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .preparingVoice, .recording, .paused, .transcribing, .coaching, .failure: true
        case .waitingForReply: false
        }
    }

    private func perform(next: ComposerState, operation: () async throws -> Void) async {
        guard !actionInFlight else { return }
        actionInFlight = true
        do { try await operation(); composer = next }
        catch { composer = .failure(.retryable) }
        actionInFlight = false
    }

    private func reloadMessages() async {
        if let loaded = try? await client.loadMessages() { messages = loaded }
    }
}
