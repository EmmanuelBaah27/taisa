import Foundation
import SwiftUI
import TaisaAudio
import TaisaConversations
import TaisaNetworking
import TaisaStorage
import TaisaVoice

struct ConversationRuntimeFactory: Sendable {
    let store: TaisaStore
    let deviceID: UUID
    let configuration: VoiceGatewayConfiguration

    func makeModel(
        route: ConversationRoute,
        entryIntent: ConversationEntryIntent?,
        dismiss: @escaping @MainActor () -> Void
    ) async throws -> ConversationViewModel {
        let conversations = ConversationRepository(store: store)
        let query = ConversationQuery(store: store)
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        if try await conversations.get(id: route.id) == nil {
            try await conversations.create(
                .init(
                    id: route.id, title: route.localTitle, lifecycle: .draft,
                    titleAuthority: .localFallback, createdAtMS: now, updatedAtMS: now
                ),
                context: mutation(at: now)
            )
        }

        let history = try await query.loadConversation(id: route.id)
        let turns = ConversationTurnRepository(store: store)
        let initial = try await turns.latestResumableTurn(conversationID: route.id) ?? makeTurn(conversationID: route.id)
        let files = try ProtectedAudioFileStore()
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
            coaching: GatewayCoachingRunner(configuration: configuration),
            connectivity: connectivity,
            reconciliation: GatewayCoachingReconciliation(configuration: configuration),
            capture: capture,
            audio: capture
        )
        let gatewayClient = GatewayConversationClient(
            store: store, deviceID: deviceID,
            coaching: GatewayCoachingRunner(configuration: configuration)
        )
        let coordinator = ConversationCoordinator.completed(
            conversationID: route.id,
            client: gatewayClient,
            voice: VoiceSessionConversationAdapter(voiceCoordinator),
            title: history.conversation.title,
            titleAuthority: history.conversation.titleAuthority
        )

        let restoredDraft = history.drafts.first
        let initialComposer: ComposerState = {
            guard entryIntent == nil, let restoredDraft else { return .waitingForReply }
            switch restoredDraft.inputMode {
            case .text: return .typing(restoredDraft.text ?? "")
            case .voice: return .paused
            }
        }()
        let initialText = restoredDraft?.inputMode == .text ? (restoredDraft?.text ?? "") : ""

        let client = ConversationScreenClient(
            loadMessages: { try await query.loadConversation(id: route.id).visibleMessages },
            beginVoice: { try await coordinator.beginReply(mode: .voice) },
            pauseVoice: { try await coordinator.pauseVoice() },
            resumeVoice: { try await coordinator.resumeVoice() },
            sendVoice: { try await coordinator.sendVoice() },
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
            correctTranscript: { messageID, text in
                _ = try await gatewayClient.correctTranscript(
                    conversationID: route.id, messageID: messageID, text: text
                )
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

    var body: some View {
        Group {
            if let model { ConversationView(model: model) }
            else if failed {
                ContentUnavailableView(
                    "Conversation unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Taisa couldn’t open this conversation securely.")
                )
            } else { ProgressView("Opening conversation…") }
        }
        .accessibilityIdentifier("conversation.root")
        .task {
            guard model == nil, !failed, let factory else { failed = true; return }
            do { model = try await factory.makeModel(route: route, entryIntent: entryIntent, dismiss: dismiss) }
            catch { failed = true }
        }
    }
}
