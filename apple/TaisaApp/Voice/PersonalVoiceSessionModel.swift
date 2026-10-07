#if TAISA_PERSONAL
import Foundation
import TaisaAudio
import TaisaNetworking
import TaisaStorage
import TaisaVoice

func voiceActionFailureStatus(_ error: any Error) -> String {
    let failure = error as NSError
    return "Voice action failed (\(failure.domain) \(failure.code))."
}

@MainActor
final class PersonalVoiceSessionModel: ObservableObject {
    @Published private(set) var snapshot: VoiceSessionSnapshot?
    @Published private(set) var status = "Configure an approved HTTPS Taisa voice gateway for this build."

    private var coordinator: VoiceSessionCoordinator?
    private var connectivityTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var conversationID: UUID?
    private var started = false

    deinit {
        connectivityTask?.cancel()
        refreshTask?.cancel()
    }

    func start() async {
        guard !started else { return }
        started = true
        do {
            let rawURL = Bundle.main.object(forInfoDictionaryKey: "TaisaVoiceGatewayURL") as? String ?? ""
            guard let url = URL(string: rawURL), !rawURL.isEmpty else { return }
            let backend = try PersonalRecoveryBackend.personal()
            let context = try await backend.voiceStoreContext()
            let deviceID = context.deviceID
            let configuration = try VoiceGatewayConfiguration(
                baseURL: url, bearerToken: deviceID.uuidString.lowercased(),
                ownerID: deviceID.uuidString.lowercased()
            )
            let conversationID = stableConversationID()
            self.conversationID = conversationID
            try await ensureConversation(conversationID, store: context.store, deviceID: deviceID)
            let turns = ConversationTurnRepository(store: context.store)
            let initial = try await turns.latestResumableTurn(
                conversationID: conversationID.uuidString
            ) ?? makeTurn(conversationID: conversationID)
            let files = try ProtectedAudioFileStore()
            let capture = AudioCaptureController(
                service: AudioCaptureService(
                    session: SystemAudioSessionAdapter(), recorder: SystemAudioRecorderAdapter(), files: files
                ),
                files: files, lifecycle: SystemAudioSessionLifecycleSource()
            )
            let connectivity = SystemConnectivityMonitor()
            let coordinator = VoiceSessionCoordinator(
                initial: initial,
                checkpoints: RepositoryVoiceTurnCheckpointer(
                    repository: turns, deviceID: deviceID
                ),
                transcription: GatewayTranscriptionRunner(configuration: configuration, audio: capture),
                transcriptionReconciliation: GatewayTranscriptionReconciliation(
                    configuration: configuration
                ),
                coaching: GatewayCoachingRunner(configuration: configuration),
                connectivity: connectivity,
                reconciliation: GatewayCoachingReconciliation(configuration: configuration),
                capture: capture, audio: capture
            )
            self.coordinator = coordinator
            snapshot = await coordinator.snapshot()
            status = "Ready"
            connectivityTask = Task { [weak self] in
                for await available in await connectivity.changes() {
                    guard !Task.isCancelled else { return }
                    try? await coordinator.connectivityChanged(isAvailable: available)
                    await self?.refresh()
                }
            }
            try await coordinator.recoverIfAuthorized()
            beginRefreshing()
        } catch {
            status = "Voice runtime configuration failed."
        }
    }

    func perform(_ action: VoiceSessionDiagnosticAction) {
        guard let coordinator else { return }
        status = "\(action.title)…"
        Task {
            do {
                switch action {
                case .record: try await coordinator.send(.startRecording)
                case .pause: try await coordinator.send(.pauseRecording)
                case .resume: try await coordinator.send(.resumeRecording)
                case .send: try await coordinator.sendRecordedAudio()
                case .cancel: try await coordinator.send(.cancel)
                case .discard: try await coordinator.send(.discard)
                case .confirmTranscript:
                    guard let text = (await coordinator.snapshot()).durable.uncertainTranscript else { return }
                    try await coordinator.send(.confirmTranscript(text: text, userMessageID: UUID().uuidString))
                case .retry: try await coordinator.send(.retry)
                case .confirmResume: try await coordinator.send(.confirmResume)
                case .nextTurn:
                    guard let conversationID else { return }
                    try await coordinator.send(.beginNextTurn(makeTurn(conversationID: conversationID)))
                }
                await refresh()
                status = "Ready"
                beginRefreshing()
            } catch {
                status = voiceActionFailureStatus(error)
                await refresh()
            }
        }
    }

    private func beginRefreshing() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self, let coordinator else { return }
            for _ in 0..<1_200 {
                guard !Task.isCancelled else { return }
                snapshot = await coordinator.snapshot()
                if snapshot?.durable.state.isTerminal == true { return }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func refresh() async {
        guard let coordinator else { return }
        snapshot = await coordinator.snapshot()
    }

    private func stableConversationID() -> UUID {
        let key = "taisa.personal.voice.conversation"
        if let value = UserDefaults.standard.string(forKey: key).flatMap(UUID.init(uuidString:)) {
            return value
        }
        let value = UUID()
        UserDefaults.standard.set(value.uuidString, forKey: key)
        return value
    }

    private func ensureConversation(_ id: UUID, store: TaisaStore, deviceID: UUID) async throws {
        let repository = ConversationRepository(store: store)
        guard try await repository.get(id: id.uuidString) == nil else { return }
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        try await repository.create(
            .init(id: id.uuidString, title: "Voice conversation", createdAtMS: now, updatedAtMS: now),
            context: .init(id: UUID().uuidString, deviceID: deviceID.uuidString, timestamp: now)
        )
    }

    private func makeTurn(conversationID: UUID) -> VoiceTurnRecord {
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        return VoiceTurnRecord(
            id: UUID().uuidString, conversationID: conversationID.uuidString,
            transcriptionRequestID: UUID().uuidString,
            transcriptionIdempotencyKey: UUID().uuidString,
            coachingRequestID: UUID().uuidString,
            coachingIdempotencyKey: UUID().uuidString,
            state: .draft, stage: .capture, createdAtMS: now, updatedAtMS: now
        )
    }
}
#endif
