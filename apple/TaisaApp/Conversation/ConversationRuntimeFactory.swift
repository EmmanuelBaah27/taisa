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
    let configuration: VoiceGatewayConfiguration?

    func seedFinalizedVoiceDraftProbe() async throws -> String {
        let conversationID = "00000000-0000-4000-8000-000000000351"
        let turnID = "00000000-0000-4000-8000-000000000352"
        let draftID = "00000000-0000-4000-8000-000000000353"
        let conversations = ConversationRepository(store: store)
        if try await conversations.draft(id: draftID) != nil { return conversationID }

        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        if try await conversations.get(id: conversationID) == nil {
            try await conversations.create(
                .init(
                    id: conversationID, title: "Saved voice draft", lifecycle: .draft,
                    titleAuthority: .localFallback, createdAtMS: now, updatedAtMS: now
                ),
                context: mutation(at: now)
            )
        }

        let files = try ProtectedAudioFileStore()
        let pending = try await files.allocate(turnID: UUID(uuidString: turnID)!)
        try Data("deterministic saved voice draft".utf8).write(to: pending.url, options: .atomic)
        let audio = try await files.finalize(pending, duration: 1)
        let turn = VoiceTurnRecord(
            id: turnID, conversationID: conversationID,
            transcriptionRequestID: "00000000-0000-4000-8000-000000000354",
            transcriptionIdempotencyKey: "saved-draft-transcription",
            coachingRequestID: "00000000-0000-4000-8000-000000000355",
            coachingIdempotencyKey: "saved-draft-coaching",
            state: .paused, stage: .capture,
            audioFileID: audio.fileID.uuidString.lowercased(), audioSHA256: audio.sha256,
            audioDurationMS: 1_000, cleanupState: .pending,
            createdAtMS: now, updatedAtMS: now
        )
        try await ConversationTurnRepository(store: store).checkpoint(
            turn, messages: [], cleanup: nil, context: mutation(at: now + 1)
        )
        try await conversations.saveDraft(.init(
            id: draftID, conversationID: conversationID, inputMode: .voice,
            text: nil, voiceTurnID: turnID, recoveryKind: .saved,
            createdAtMS: now, updatedAtMS: now
        ))
        return conversationID
    }

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
            let local = "result=draft input=voice state=\(turn.state.rawValue) stage=\(turn.stage.rawValue) failure=\(turn.failureCode ?? "none")"
            guard turn.stage == .coaching,
                  let requestID = UUID(uuidString: turn.coachingRequestID) else {
                return local
            }
            guard let configuration else {
                return "\(local) reconciliation=gateway-unavailable"
            }
            do {
                let result = try await GatewayCoachingReconciliation(configuration: configuration)
                    .reconcile(requestID: requestID)
                let status: String
                switch result {
                case .safeToRetry: status = "safe-to-retry"
                case .ambiguous: status = "ambiguous"
                case .completed: status = "completed"
                case .failed(_, let retryable): status = retryable ? "failed-retryable" : "failed-terminal"
                }
                return "\(local) reconciliation=\(status)"
            } catch {
                return "\(local) reconciliation=lookup-failed type=\(String(reflecting: type(of: error)))"
            }
        } catch {
            return "result=diagnostic-read-failed type=\(String(reflecting: type(of: error)))"
        }
    }

    func retryLatestPreservedDraftProbe() async -> String {
        do {
            let snapshot = try await ConversationQuery(store: store).loadIndex()
            guard let draft = snapshot.drafts.first else { return "result=no-draft" }
            let model = try await makeModel(
                route: .init(id: draft.conversationID, localTitle: "Draft"),
                entryIntent: nil,
                dismiss: {}
            )
            await model.start()
            await model.retry()
            return await contentFreeLatestDraftDiagnostic()
        } catch {
            return "result=retry-probe-failed type=\(String(reflecting: type(of: error)))"
        }
    }

    func cleanupCompletedPreservedDraftProbe() async -> String {
        do {
            let snapshot = try await ConversationQuery(store: store).loadIndex()
            guard let draft = snapshot.drafts.first else { return "result=no-draft" }
            _ = try await makeModel(
                route: .init(id: draft.conversationID, localTitle: "Draft"),
                entryIntent: nil,
                dismiss: {}
            )
            return await contentFreeLatestDraftDiagnostic()
        } catch {
            return "result=cleanup-probe-failed type=\(String(reflecting: type(of: error)))"
        }
    }

    func makeModel(
        route: ConversationRoute,
        entryIntent: ConversationEntryIntent?,
        dismiss: @escaping @MainActor () -> Void
    ) async throws -> ConversationViewModel {
        let conversations = ConversationRepository(store: store)
        let query = ConversationQuery(store: store)
        let assistantResponses = AssistantResponseRepository(store: store)
        let proposalRouter = AssistantProposalRouter(store: store)
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
        guard let configuration else {
            return await makeLocalModel(
                route: route,
                entryIntent: entryIntent,
                history: history,
                query: query,
                conversations: conversations,
                dismiss: dismiss
            )
        }
        let turns = ConversationTurnRepository(store: store)
        let rawResumable = try await openStage(.resumableTurn) {
            try await turns.latestResumableTurn(conversationID: route.id)
        }
        let latestCompleted = try await openStage(.resumableTurn) {
            try await turns.latestCompletedTurn(conversationID: route.id)
        }
        let resumable: VoiceTurnRecord? = if let rawResumable, let latestCompleted,
                                            latestCompleted.updatedAtMS > rawResumable.updatedAtMS {
            nil
        } else {
            rawResumable
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
                        || latestCompleted.map { $0.updatedAtMS > draft.updatedAtMS } == true
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
        let preferenceSignals: @Sendable () async throws -> [[String: String]] = {
            let repository = AssistantResponseRepository(store: store)
            let feedback = try await repository.recentFeedback()
            let derived = ResponsePreferenceProfile.derive(from: feedback)
            try await repository.replacePreferenceProfile(
                derived.map { .init(factor: $0.factor, direction: $0.direction) },
                updatedAtMS: feedback.map(\.updatedAtMS).max() ?? 0
            )
            return try await repository.preferenceProfile().map {
                ["factor": $0.factor.rawValue, "direction": $0.direction.rawValue]
            }
        }
        let voiceCoordinator = VoiceSessionCoordinator(
            initial: initial,
            checkpoints: RepositoryVoiceTurnCheckpointer(repository: turns, deviceID: deviceID),
            transcription: GatewayTranscriptionRunner(configuration: configuration, audio: capture),
            transcriptionReconciliation: GatewayTranscriptionReconciliation(configuration: configuration),
            coaching: GatewayCoachingRunner(configuration: configuration, recentMessages: messageHistory, preferenceSignals: preferenceSignals),
            connectivity: connectivity,
            reconciliation: GatewayCoachingReconciliation(configuration: configuration),
            capture: capture,
            audio: capture
        )
        let gatewayClient = GatewayConversationClient(
            store: store, deviceID: deviceID,
            coaching: GatewayCoachingRunner(configuration: configuration, recentMessages: messageHistory, preferenceSignals: preferenceSignals)
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
        let restoredDraftID = restoredDraft?.id

        let client = ConversationScreenClient(
            loadMessages: { try await query.loadConversation(id: route.id).visibleMessages },
            loadAssistantResponses: {
                let values = try await query.loadConversation(id: route.id).assistantResponses
                return try await assistantResponses.resolveSources(in: values)
            },
            loadTitle: { try await query.loadConversation(id: route.id).conversation.title },
            beginVoice: { try await coordinator.beginReply(mode: .voice) },
            pauseVoice: { try await coordinator.pauseVoice() },
            resumeVoice: { try await coordinator.resumeVoice() },
            retryPauseVoice: { try await voiceCoordinator.retryCapturePause() },
            retryResumeVoice: { try await voiceCoordinator.retryCaptureResume() },
            sendVoice: { transcriptAvailable in
                try await coordinator.sendVoice(onTranscriptAvailable: transcriptAvailable)
                let snapshot = try await query.loadConversation(id: route.id)
                for draft in snapshot.drafts { try await conversations.discardDraft(id: draft.id) }
            },
            sendText: { try await coordinator.send(.text($0)) },
            retry: {
                try await coordinator.retry()
                if let restoredDraftID {
                    try await conversations.discardDraft(id: restoredDraftID)
                }
            },
            saveDraft: { input in
                switch input {
                case .text:
                    try await gatewayClient.saveDraft(conversationID: route.id, input: input)
                case .voice:
                    try await voiceAdapter.saveDraft()
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
            },
            loadCaptureSnapshot: { await voiceCoordinator.snapshot().capture },
            loadPartialCoaching: { await voiceCoordinator.snapshot().partialCoaching },
            recoveryEvents: {
                AsyncStream { continuation in
                    let task = Task {
                        let changes = await connectivity.changes()
                        for await isAvailable in changes where isAvailable {
                            let before = await voiceCoordinator.snapshot().durable.state
                            guard before != .completed else { continue }
                            try? await voiceCoordinator.connectivityChanged(isAvailable: true)
                            await voiceCoordinator.waitForIdle()
                            if await voiceCoordinator.snapshot().durable.state == .completed {
                                continuation.yield(())
                            }
                        }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
            saveFeedback: {
                try await assistantResponses.upsertFeedback($0)
                try await Self.materializePreferenceProfile(assistantResponses, revision: $0.updatedAtMS)
            },
            removeFeedback: { responseMessageID, revision in
                try await assistantResponses.removeFeedback(responseMessageID: responseMessageID)
                try await Self.materializePreferenceProfile(assistantResponses, revision: revision)
            },
            acceptProposal: { proposalID in
                _ = try await proposalRouter.accept(
                    proposalID: proposalID, deviceID: deviceID,
                    resolvedAtMS: Int64(Date().timeIntervalSince1970 * 1_000)
                )
            },
            dismissProposal: { proposalID in
                _ = try await proposalRouter.dismiss(
                    proposalID: proposalID, deviceID: deviceID,
                    resolvedAtMS: Int64(Date().timeIntervalSince1970 * 1_000)
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

    @MainActor
    private func makeLocalModel(
        route: ConversationRoute,
        entryIntent: ConversationEntryIntent?,
        history: ConversationSnapshot,
        query: ConversationQuery,
        conversations: ConversationRepository,
        dismiss: @escaping @MainActor () -> Void
    ) -> ConversationViewModel {
        let unavailable: @Sendable () async throws -> Void = {
            throw ConversationFailure.unavailable
        }
        let assistantResponses = AssistantResponseRepository(store: store)
        let proposalRouter = AssistantProposalRouter(store: store)
        let textDraft = history.drafts.first(where: { $0.inputMode == .text })?.text ?? ""
        let composer: ComposerState = textDraft.isEmpty ? .waitingForReply : .typing(textDraft)
        let client = ConversationScreenClient(
            loadMessages: { try await query.loadConversation(id: route.id).visibleMessages },
            loadAssistantResponses: {
                let values = try await query.loadConversation(id: route.id).assistantResponses
                return try await assistantResponses.resolveSources(in: values)
            },
            loadTitle: { try await query.loadConversation(id: route.id).conversation.title },
            beginVoice: unavailable,
            pauseVoice: unavailable,
            resumeVoice: unavailable,
            sendVoice: { _ in try await unavailable() },
            sendText: { _ in try await unavailable() },
            retry: unavailable,
            saveDraft: { input in
                guard case .text = input else { try await unavailable(); return }
                try await conversations.saveDraft(.init(
                    id: Self.derivedUUID(from: route.id, salt: 4),
                    conversationID: route.id,
                    inputMode: .text,
                    text: {
                        if case .text(let text) = input { return text }
                        return ""
                    }(),
                    voiceTurnID: nil,
                    recoveryKind: .saved,
                    createdAtMS: Int64(Date().timeIntervalSince1970 * 1_000),
                    updatedAtMS: Int64(Date().timeIntervalSince1970 * 1_000)
                ))
            },
            discardDraft: {
                let snapshot = try await query.loadConversation(id: route.id)
                for draft in snapshot.drafts { try await conversations.discardDraft(id: draft.id) }
            },
            discardEmptyConversation: {
                let snapshot = try await query.loadConversation(id: route.id)
                guard snapshot.conversation.lifecycle == .draft,
                      snapshot.drafts.isEmpty,
                      snapshot.visibleMessages.isEmpty else { return }
                try await conversations.delete(
                    id: route.id,
                    context: mutation(at: Int64(Date().timeIntervalSince1970 * 1_000))
                )
            },
            correctTranscript: { _, _ in try await unavailable() },
            saveFeedback: {
                try await assistantResponses.upsertFeedback($0)
                try await Self.materializePreferenceProfile(assistantResponses, revision: $0.updatedAtMS)
            },
            removeFeedback: { responseMessageID, revision in
                try await assistantResponses.removeFeedback(responseMessageID: responseMessageID)
                try await Self.materializePreferenceProfile(assistantResponses, revision: revision)
            },
            acceptProposal: { proposalID in
                _ = try await proposalRouter.accept(
                    proposalID: proposalID, deviceID: deviceID,
                    resolvedAtMS: Int64(Date().timeIntervalSince1970 * 1_000)
                )
            },
            dismissProposal: { proposalID in
                _ = try await proposalRouter.dismiss(
                    proposalID: proposalID, deviceID: deviceID,
                    resolvedAtMS: Int64(Date().timeIntervalSince1970 * 1_000)
                )
            }
        )
        return ConversationViewModel(
            conversationID: route.id,
            title: history.conversation.title,
            entryIntent: entryIntent,
            composer: composer,
            text: textDraft,
            client: client,
            dismiss: dismiss
        )
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
            case .paused where linkedVoiceTurn?.audioSHA256 != nil
                && linkedVoiceTurn?.audioDurationMS != nil:
                composer = .savedVoiceDraft
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

    static func materializePreferenceProfile(
        _ repository: AssistantResponseRepository,
        revision: Int64
    ) async throws {
        let feedback = try await repository.recentFeedback()
        let derived = ResponsePreferenceProfile.derive(from: feedback)
        try await repository.replacePreferenceProfile(
            derived.map { .init(factor: $0.factor, direction: $0.direction) },
            updatedAtMS: max(revision, feedback.map(\.updatedAtMS).max() ?? 0)
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
