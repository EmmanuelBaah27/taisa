import AVFAudio
import Foundation
import Observation
import TaisaCareerWork
import TaisaConversations
import TaisaHome
import TaisaStorage
import TaisaVoice
import TaisaYou

@MainActor
@Observable
final class AppRuntime {
    struct Clients: Sendable {
        let home: HomeClient
        let you: YouClient
        let careerWork: CareerWorkClient
        let insights: InsightsClient
        let conversations: ConversationsClient
        let conversationFactory: ConversationRuntimeFactory?

        init(home: HomeClient, you: YouClient, insights: InsightsClient,
             careerWork: CareerWorkClient = CareerWorkClient(loadOverview: { .init(active: [], paused: [], completed: [], archived: []) }),
             conversations: ConversationsClient = ConversationsClient(load: { ConversationIndexSnapshot(drafts: [], conversations: []) }),
             conversationFactory: ConversationRuntimeFactory? = nil) {
            self.home = home
            self.you = you
            self.careerWork = careerWork
            self.insights = insights
            self.conversations = conversations
            self.conversationFactory = conversationFactory
        }
    }

    enum State: Equatable { case startup, ready, recoveryRequired }

    private(set) var state: State = .startup
    private(set) var homeModel: HomeModel?
    private(set) var careerWorkModel: CareerWorkModel?
    private(set) var insightsModel: InsightsModel?
    private(set) var conversationsModel: ConversationsModel?
    private(set) var youModel: YouModel?
    private(set) var conversationFactory: ConversationRuntimeFactory?
    let primaryShellModel: PrimaryAppShellModel
    @ObservationIgnored private let startOperation: @Sendable () async throws -> Clients

    init(primaryShellModel: PrimaryAppShellModel = PrimaryAppShellModel(),
         start: @escaping @Sendable () async throws -> Clients) {
        self.primaryShellModel = primaryShellModel
        startOperation = start
    }

    static func live() -> AppRuntime {
        return AppRuntime {
#if DEBUG || TAISA_PERSONAL
            if ProcessInfo.processInfo.arguments.contains("--taisa-recovery-route-qa") {
                throw StorageError.authenticationFailed
            }
#endif
            let backend = try PersonalRecoveryBackend.personal()
            let context = try await backend.voiceStoreContext()
            let store = context.store
            let rawURL = Bundle.main.object(forInfoDictionaryKey: "TaisaVoiceGatewayURL") as? String ?? ""
            let configuration: VoiceGatewayConfiguration?
#if DEBUG || TAISA_PERSONAL
            if ProcessInfo.processInfo.arguments.contains("--taisa-seed-finalized-voice-draft") {
                configuration = try VoiceGatewayConfiguration(
                    baseURL: URL(string: "https://voice.example.com")!,
                    bearerToken: "saved-draft-ui-probe",
                    ownerID: "00000000-0000-4000-8000-000000000350"
                )
            } else {
                configuration = try await voiceConfiguration(
                    gatewayURLString: rawURL,
                    credentialStore: KeychainVoiceGatewayCredentialStore()
                )
            }
#else
            configuration = try await voiceConfiguration(
                gatewayURLString: rawURL,
                credentialStore: KeychainVoiceGatewayCredentialStore()
            )
#endif
            let hasGatewayConfiguration = configuration != nil
            return Clients(
                home: HomeClient.local(store: store, deviceID: context.deviceID.uuidString),
                you: YouClient.local(
                    store: store,
                    deviceID: context.deviceID.uuidString,
                    operational: {
                        await AppRuntime.liveOperationalFacts(
                            hasGatewayConfiguration: hasGatewayConfiguration
                        )
                    }
                ),
                insights: InsightsClient.local(store: store),
                careerWork: CareerWorkClient.local(store: store, deviceID: context.deviceID.uuidString),
                conversations: ConversationsClient.local(store: store),
                conversationFactory: configuration.map { ConversationRuntimeFactory(store: store, deviceID: context.deviceID, configuration: $0) }
            )
        }
    }

    static func voiceConfiguration(
        gatewayURLString: String,
        credentialStore: any VoiceGatewayCredentialStoring
    ) async throws -> VoiceGatewayConfiguration? {
        guard let gatewayURL = URL(string: gatewayURLString),
              let credential = try await credentialStore.load(origin: gatewayURL)
        else { return nil }
        return try VoiceGatewayConfiguration(
            baseURL: credential.origin,
            bearerToken: credential.bearerToken,
            ownerID: credential.credentialID
        )
    }

    nonisolated static func operationalFacts(
        hasGatewayConfiguration: Bool,
        microphone: YouPermissionStatus
    ) -> YouOperationalFacts {
        .init(
            store: .healthy,
            recovery: .unknown,
            microphone: microphone,
            gateway: hasGatewayConfiguration ? .unknown : .unavailable,
            appProtection: .unknown
        )
    }

    private static func liveOperationalFacts(
        hasGatewayConfiguration: Bool
    ) -> YouOperationalFacts {
        operationalFacts(
            hasGatewayConfiguration: hasGatewayConfiguration,
            microphone: microphonePermissionStatus
        )
    }

    @discardableResult
    func start() async -> State {
        guard state == .startup else { return state }
        return await openServices()
    }

    @discardableResult
    func retryRecovery() async -> State {
        guard state == .recoveryRequired else { return state }
        state = .startup
        return await openServices()
    }

    @discardableResult
    func reloadAfterRestore() async -> State {
        state = .startup
        clearServices()
        return await openServices()
    }

    private func openServices() async -> State {
        do {
            let clients = try await startOperation()
            homeModel = HomeModel(client: clients.home)
            youModel = YouModel(client: clients.you)
            careerWorkModel = CareerWorkModel(client: clients.careerWork)
            insightsModel = InsightsModel(client: clients.insights)
            conversationsModel = ConversationsModel(client: clients.conversations)
            conversationFactory = clients.conversationFactory
            state = .ready
        } catch {
            clearServices()
            state = .recoveryRequired
        }
        return state
    }

    private func clearServices() {
        homeModel = nil
        youModel = nil
        careerWorkModel = nil
        insightsModel = nil
        conversationsModel = nil
        conversationFactory = nil
    }

    func requireRecovery() { state = .recoveryRequired }

    private static var microphonePermissionStatus: YouPermissionStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        case .undetermined: .notDetermined
        @unknown default: .restricted
        }
    }
}
