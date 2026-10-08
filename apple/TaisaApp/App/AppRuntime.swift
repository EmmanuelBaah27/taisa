import Foundation
import Observation
import TaisaConversations
import TaisaHome
import TaisaStorage
import TaisaVoice

@MainActor
@Observable
final class AppRuntime {
    struct Clients: Sendable {
        let home: HomeClient
        let insights: InsightsClient
        let conversations: ConversationsClient
        let conversationFactory: ConversationRuntimeFactory?

        init(home: HomeClient, insights: InsightsClient,
             conversations: ConversationsClient = ConversationsClient(load: { ConversationIndexSnapshot(drafts: [], conversations: []) }),
             conversationFactory: ConversationRuntimeFactory? = nil) {
            self.home = home
            self.insights = insights
            self.conversations = conversations
            self.conversationFactory = conversationFactory
        }
    }

    enum State: Equatable { case startup, ready, recoveryRequired }

    private(set) var state: State = .startup
    private(set) var homeModel: HomeModel?
    private(set) var insightsModel: InsightsModel?
    private(set) var conversationsModel: ConversationsModel?
    private(set) var conversationFactory: ConversationRuntimeFactory?
    let primaryShellModel: PrimaryAppShellModel
    @ObservationIgnored private let startOperation: @Sendable () async throws -> Clients

    init(primaryShellModel: PrimaryAppShellModel = PrimaryAppShellModel(),
         start: @escaping @Sendable () async throws -> Clients) {
        self.primaryShellModel = primaryShellModel
        startOperation = start
    }

    static func live() -> AppRuntime {
        AppRuntime {
            let backend = try PersonalRecoveryBackend.personal()
            let context = try await backend.voiceStoreContext()
            let store = context.store
            let rawURL = Bundle.main.object(forInfoDictionaryKey: "TaisaVoiceGatewayURL") as? String ?? ""
            let configuration = try await voiceConfiguration(
                gatewayURLString: rawURL,
                credentialStore: KeychainVoiceGatewayCredentialStore()
            )
            return Clients(
                home: HomeClient.local(store: store, deviceID: context.deviceID.uuidString),
                insights: InsightsClient.local(store: store),
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

    @discardableResult
    func start() async -> State {
        guard state == .startup else { return state }
        do {
            let clients = try await startOperation()
            homeModel = HomeModel(client: clients.home)
            insightsModel = InsightsModel(client: clients.insights)
            conversationsModel = ConversationsModel(client: clients.conversations)
            conversationFactory = clients.conversationFactory
            state = .ready
        } catch {
            homeModel = nil
            insightsModel = nil
            conversationsModel = nil
            conversationFactory = nil
            state = .recoveryRequired
        }
        return state
    }

    func requireRecovery() { state = .recoveryRequired }
}
