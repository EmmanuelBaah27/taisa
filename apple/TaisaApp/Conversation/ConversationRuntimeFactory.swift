import Foundation
import SwiftUI
import TaisaAudio
import TaisaConversations
import TaisaNetworking
import TaisaStorage
import TaisaVoice

enum ConversationOpenStage: String, Sendable {
    case conversationFactory = "conversation-factory"
    case conversationRecord = "conversation-record"
    case history = "history"
    case resumableTurn = "resumable-turn"
    case draftCleanup = "draft-cleanup"
    case refreshedHistory = "refreshed-history"
    case audioFiles = "audio-files"
    case unknown
}

struct ConversationOpenFailure: Error, Sendable {
    let stage: ConversationOpenStage
}

struct ConversationRuntimeFactory: Sendable {
    struct Restoration {
        let voiceTurn: VoiceTurnRecord
        let composer: ComposerState
        let text: String
    }

    let store: TaisaStore
    let deviceID: UUID
    let configuration: VoiceGatewayConfiguration

    func contentFreeLatestDraftDiagnostic() async -> String {
        do {
            let snapshot = try await ConversationQuery(store: store).loadIndex()
            guard let draft = snapshot.drafts.first else { return "result=no-draft" }
            guard let turnID = draft.voiceTurnID else {
                return "result=draft input=\(draft.inputMode.rawValue) turn=none"
            }
            guard let turn = try await ConversationTurnRepository(store: store).turn(id: turnID) else {
                return "result=draft input=voice turn=missing"
            }
            return "result=draft input=voice state=\(turn.state.rawValue) stage=\(turn.stage.rawValue) failure=\(turn.failureCode ?? "none")"
        } catch {
            return "result=diagnostic-read-failed type=\(String(reflecting: type(of: error)))"
        }
    }

    func makeModel(
        route: ConversationRoute,
        entryIntent: ConversationEntryIntent?,
        dismiss: @escaping @MainActor () -> Void
    ) async throws -> ConversationViewModel {
        let conversations = ConversationRepository(store: store)
        let query = ConversationQuery(store: store)
        let messageHistory: @Sendable (String) async throws -> [MessageRecord] = { conversationID in
            try await query.loadConversation(id: conversationID).visibleMessages
        }
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        if try await openStage(.conversationRecord, operation: {
            try await conversations.get(id: route.id)
        }) == nil {
            try await openStage(.conversationRecord) {
                try await conversations.create(
                .init(
                    id: route.id, title: route.localTitle, lifecycle: .draft,
                    titleAuthority: .localFallback, createdAtMS: now, updatedAtMS: now
                ),
                context: mutation(at: now)
            )
            }
        }

        var history = try await openStage(.history) {
            try await query.loadConversation(id: route.id)
        }
        let turns = ConversationTurnRepository(store: store)
        let resumable = try await openStage(.resumableTurn) {
            try await turns.latestResumableTurn(conversationID: route.id)
        }
        let pendingConversationRequest = resumable.flatMap { turn in
            ["pending_text", "pending_correction"].contains(turn.failureCode) ? turn : nil
        }
        let lastUserMessage = history.visibleMessages.last(where: { $0.role == "user" })
        if pendingConversationRequest == nil {
            for draft in history.drafts {
                let isCompletedText = draft.inputMode == .text
                    && draft.recoveryKind == .retryableCoaching
                    && draft.text == lastUserMessage?.body
                let isCompletedVoice: Bool
                if let voiceTurnID = draft.voiceTurnID,
                   let voiceTurn = try? await turns.turn(id: voiceTurnID) {
                    isCompletedVoice = voiceTurn.state == .completed
                } else {
                    isCompletedVoice = false
                }
                if isCompletedText || isCompletedVoice {
                    try await openStage(.draftCleanup) {
                        try await conversations.discardDraft(id: draft.id)
                    }
                }
            }
            history = try await openStage(.refreshedHistory) {
                try await query.loadConversation(id: route.id)
            }
        }
        let restoredDraft = history.drafts.first
        let linkedVoiceTurn: VoiceTurnRecord?
        if restoredDraft?.inputMode == .voice, let voiceTurnID = restoredDraft?.voiceTurnID {
            linkedVoiceTurn = try? await turns.turn(id: voiceTurnID)
        } else {
            linkedVoiceTurn = nil
        }
        let recoveryTranscript: String?
        if linkedVoiceTurn == nil,
           restoredDraft?.inputMode == .voice,
           let voiceTurnID = restoredDraft?.voiceTurnID {
            recoveryTranscript = try? await turns.recoveryTranscript(
                turnID: voiceTurnID,
                conversationID: route.id
            )
        } else {
            recoveryTranscript = nil
        }
        let fallbackTurn = makeTurn(conversationID: route.id)
        let restoration = Self.restoration(
            draft: restoredDraft,
            linkedVoiceTurn: linkedVoiceTurn,
            resumableVoiceTurn: resumable,
            fallbackVoiceTurn: fallbackTurn,
            recoveryTranscript: recoveryTranscript ?? lastUserMessage?.body
        )
        let initial = pendingConversationRequest == nil ? restoration.voiceTurn : fallbackTurn
        let files = try await openStage(.audioFiles) {
            try ProtectedAudioFileStore()
        }
        let capture = AudioCaptureController(
            service: AudioCaptureService(
                session: SystemAudioSessionAdapter(), recorder: SystemAudioRecorderAdapter(), files: files
            ),
            files: files,
            lifecycle: SystemAudioSessionLifecycleSource()
        )
        let connectivity = SystemConnectivityMonitor()
        let voiceCoordinator = VoiceSessionCoordinator(
            initial: initial,
            checkpoints: RepositoryVoiceTurnCheckpointer(repository: turns, deviceID: deviceID),
            transcription: GatewayTranscriptionRunner(configuration: configuration, audio: capture),
            transcriptionReconciliation: GatewayTranscriptionReconciliation(configuration: configuration),
            coaching: GatewayCoachingRunner(configuration: configuration, recentMessages: messageHistory),
            connectivity: connectivity,
            reconciliation: GatewayCoachingReconciliation(configuration: configuration),
            capture: capture,
            audio: capture
        )
        let gatewayClient = GatewayConversationClient(
            store: store, deviceID: deviceID,
            coaching: GatewayCoachingRunner(configuration: configuration, recentMessages: messageHistory)
        )
        let voiceAdapter = VoiceSessionConversationAdapter(voiceCoordinator)
        let coordinator: ConversationCoordinator
        if let pending = pendingConversationRequest,
           let text = pending.acceptedTranscript,
           pending.failureCode == "pending_correction",
           let messageID = pending.userMessageID {
            coordinator = .restoredCorrectionRequest(
                conversationID: route.id, requestID: pending.coachingRequestID,
                messageID: messageID, text: text, client: gatewayClient,
                voice: voiceAdapter, title: history.conversation.title,
                titleAuthority: history.conversation.titleAuthority
            )
        } else if let pending = pendingConversationRequest,
                  let text = pending.acceptedTranscript {
            coordinator = .restoredTextRequest(
                conversationID: route.id, requestID: pending.coachingRequestID,
                text: text, client: gatewayClient, voice: voiceAdapter
            )
        } else {
            coordinator = .completed(
                conversationID: route.id, client: gatewayClient, voice: voiceAdapter,
                title: history.conversation.title,
                titleAuthority: history.conversation.titleAuthority
            )
        }

        let initialComposer = pendingConversationRequest == nil
            ? (entryIntent == nil ? restoration.composer : .waitingForReply)
            : .failure(.retryable)
        let initialText = restoration.text

        let client = ConversationScreenClient(
            loadMessages: { try await query.loadConversation(id: route.id).visibleMessages },
            loadTitle: { try await query.loadConversation(id: route.id).conversation.title },
            beginVoice: { try await coordinator.beginReply(mode: .voice) },
            pauseVoice: { try await coordinator.pauseVoice() },
            resumeVoice: { try await coordinator.resumeVoice() },
            sendVoice: { transcriptAvailable in
                try await coordinator.sendVoice(onTranscriptAvailable: transcriptAvailable)
                let snapshot = try await query.loadConversation(id: route.id)
                for draft in snapshot.drafts { try await conversations.discardDraft(id: draft.id) }
            },
            sendText: { try await coordinator.send(.text($0)) },
            retry: { try await coordinator.retry() },
            saveDraft: { input in
                switch input {
                case .text:
                    try await gatewayClient.saveDraft(conversationID: route.id, input: input)
                case .voice:
                    let snapshot = await voiceCoordinator.snapshot()
                    if snapshot.durable.state == .recording { try await coordinator.pauseVoice() }
                    let paused = await voiceCoordinator.snapshot().durable
                    try await conversations.saveDraft(.init(
                        id: Self.derivedUUID(from: paused.id, salt: 4),
                        conversationID: route.id, inputMode: .voice, text: nil,
                        voiceTurnID: paused.id, recoveryKind: .saved,
                        createdAtMS: paused.createdAtMS, updatedAtMS: paused.updatedAtMS
                    ))
                }
            },
            discardDraft: {
                let snapshot = try await query.loadConversation(id: route.id)
                for draft in snapshot.drafts { try await conversations.discardDraft(id: draft.id) }
                let voice = await voiceCoordinator.snapshot().durable
                if !voice.state.isTerminal && voice.state != .discarded { try await voiceCoordinator.send(.discard) }
            },
            discardEmptyConversation: {
                let snapshot = try await query.loadConversation(id: route.id)
                guard snapshot.conversation.lifecycle == .draft, snapshot.drafts.isEmpty else { return }
                let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
                for message in snapshot.visibleMessages {
                    try await conversations.deleteMessage(id: message.id, context: mutation(at: timestamp))
                }
                try await conversations.delete(id: route.id, context: mutation(at: timestamp))
            },
            correctTranscript: { messageID, text in
                try await coordinator.correctTranscript(messageID: messageID, text: text)
            }
        )
        return await ConversationViewModel(
            conversationID: route.id,
            title: history.conversation.title,
            entryIntent: entryIntent,
            composer: initialComposer,
            text: initialText,
            client: client,
            dismiss: dismiss
        )
    }

    private func mutation(at timestamp: Int64) -> MutationContext {
        .init(id: UUID().uuidString, deviceID: deviceID.uuidString, timestamp: timestamp)
    }

    private func openStage<Value>(
        _ stage: ConversationOpenStage,
        operation: () async throws -> Value
    ) async throws -> Value {
        do {
            return try await operation()
        } catch {
            throw ConversationOpenFailure(stage: stage)
        }
    }

    static func restoration(
        draft: ConversationDraftRecord?,
        linkedVoiceTurn: VoiceTurnRecord?,
        resumableVoiceTurn: VoiceTurnRecord?,
        fallbackVoiceTurn: VoiceTurnRecord,
        recoveryTranscript: String? = nil
    ) -> Restoration {
        var voiceTurn = linkedVoiceTurn ?? resumableVoiceTurn ?? fallbackVoiceTurn
        guard let draft else {
            return Restoration(voiceTurn: voiceTurn, composer: .waitingForReply, text: "")
        }
        switch draft.inputMode {
        case .text:
            let text = draft.text ?? ""
            return Restoration(voiceTurn: voiceTurn, composer: .typing(text), text: text)
        case .voice:
            let composer: ComposerState
            switch linkedVoiceTurn?.state {
            case .recoverableFailure, .terminalFailure:
                composer = .failure(.retryable)
            default:
                if linkedVoiceTurn == nil,
                   let transcript = recoveryTranscript?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !transcript.isEmpty {
                    voiceTurn = VoiceTurnRecord(
                        id: fallbackVoiceTurn.id,
                        conversationID: fallbackVoiceTurn.conversationID,
                        transcriptionRequestID: fallbackVoiceTurn.transcriptionRequestID,
                        transcriptionIdempotencyKey: fallbackVoiceTurn.transcriptionIdempotencyKey,
                        coachingRequestID: fallbackVoiceTurn.coachingRequestID,
                        coachingIdempotencyKey: fallbackVoiceTurn.coachingIdempotencyKey,
                        state: .terminalFailure,
                        stage: .finished,
                        acceptedTranscript: transcript,
                        failureCode: "legacy_voice_turn_unavailable",
                        createdAtMS: fallbackVoiceTurn.createdAtMS,
                        updatedAtMS: fallbackVoiceTurn.updatedAtMS
                    )
                    composer = .failure(.retryable)
                } else {
                    composer = .paused
                }
            }
            return Restoration(voiceTurn: voiceTurn, composer: composer, text: "")
        }
    }

    private func makeTurn(conversationID: String) -> VoiceTurnRecord {
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        return .init(
            id: UUID().uuidString, conversationID: conversationID,
            transcriptionRequestID: UUID().uuidString, transcriptionIdempotencyKey: UUID().uuidString,
            coachingRequestID: UUID().uuidString, coachingIdempotencyKey: UUID().uuidString,
            state: .draft, stage: .capture, createdAtMS: now, updatedAtMS: now
        )
    }

    private static func derivedUUID(from source: String, salt: UInt8) -> String {
        guard var uuid = UUID(uuidString: source)?.uuid else { return UUID().uuidString.lowercased() }
        uuid.15 ^= salt
        return UUID(uuid: uuid).uuidString.lowercased()
    }
}

struct ConversationHostView: View {
    let route: ConversationRoute
    let entryIntent: ConversationEntryIntent?
    let factory: ConversationRuntimeFactory?
    let dismiss: @MainActor () -> Void
    @State private var model: ConversationViewModel?
    @State private var failed = false
    @State private var failureStage: ConversationOpenStage?

    var body: some View {
        Group {
            if let model { ConversationView(model: model) }
            else if failed {
                VStack {
                    ContentUnavailableView {
                        Label("Conversation unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("Taisa couldn’t open this conversation securely.")
                    } actions: {
                        Button("Close", action: dismiss)
                            .accessibilityIdentifier("conversation.unavailable.close")
                    }
#if DEBUG || TAISA_PERSONAL
                    Text("Diagnostic: \((failureStage ?? .unknown).rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("conversation.unavailable.diagnostic")
#endif
                }
            } else { ProgressView("Opening conversation…") }
        }
        .accessibilityIdentifier("conversation.root")
        .task {
            print("TAISA_CONVERSATION_OPEN stage=host-start")
#if DEBUG || TAISA_PERSONAL
            if ProcessInfo.processInfo.arguments.contains("--taisa-conversation-route-qa-fixture") {
                guard entryIntent == .voice else { failed = true; return }
                model = .preview(composer: .recording)
                return
            }
#endif
            guard model == nil, !failed else { return }
            guard let factory else {
                failureStage = .conversationFactory
                print("TAISA_CONVERSATION_OPEN_FAILURE stage=conversation-factory")
                failed = true
                return
            }
            do {
                model = try await factory.makeModel(route: route, entryIntent: entryIntent, dismiss: dismiss)
                print("TAISA_CONVERSATION_OPEN result=success")
            }
            catch {
                failureStage = (error as? ConversationOpenFailure)?.stage ?? .unknown
                print("TAISA_CONVERSATION_OPEN_FAILURE stage=\(failureStage?.rawValue ?? "unknown")")
                failed = true
            }
        }
    }
}
