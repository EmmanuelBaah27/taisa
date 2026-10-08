import Foundation
import Observation
import TaisaHome
import TaisaConversations
import TaisaStorage
import TaisaVoice

@MainActor
@Observable
final class AppRuntime {
    enum State: Equatable {
        case startup
        case ready
        case recoveryRequired
    }

    private(set) var state: State = .startup
    private(set) var homeModel: HomeModel?
    private(set) var conversationsModel: ConversationsModel?
    private(set) var conversationFactory: ConversationRuntimeFactory?
    let primaryShellModel: PrimaryAppShellModel
    @ObservationIgnored private let startOperation: @Sendable () async throws -> (HomeClient, ConversationsClient, ConversationRuntimeFactory?)

    init(
        primaryShellModel: PrimaryAppShellModel = PrimaryAppShellModel(),
        start: @escaping @Sendable () async throws -> HomeClient
    ) {
        self.primaryShellModel = primaryShellModel
        startOperation = {
            (try await start(), ConversationsClient(load: { ConversationIndexSnapshot(drafts: [], conversations: []) }), nil)
        }
    }

    private init(
        primaryShellModel: PrimaryAppShellModel = PrimaryAppShellModel(),
        startServices: @escaping @Sendable () async throws -> (HomeClient, ConversationsClient, ConversationRuntimeFactory?)
    ) {
        self.primaryShellModel = primaryShellModel
        startOperation = startServices
    }

    static func live() -> AppRuntime {
        AppRuntime(startServices: {
            let backend = try PersonalRecoveryBackend.personal()
            let context = try await backend.voiceStoreContext()
            let store = context.store
            let rawURL = Bundle.main.object(forInfoDictionaryKey: "TaisaVoiceGatewayURL") as? String ?? ""
            let configuration = URL(string: rawURL).flatMap {
                try? VoiceGatewayConfiguration(
                    baseURL: $0, bearerToken: context.deviceID.uuidString.lowercased(),
                    ownerID: context.deviceID.uuidString.lowercased()
                )
            }
            return (
                HomeClient { try await HomeQuery(store: store).load() },
                ConversationsClient.local(store: store),
                configuration.map { ConversationRuntimeFactory(store: store, deviceID: context.deviceID, configuration: $0) }
            )
        })
    }

    @discardableResult
    func start() async -> State {
        guard state == .startup else { return state }
        do {
            let services = try await startOperation()
            homeModel = HomeModel(client: services.0)
            conversationsModel = ConversationsModel(client: services.1)
            conversationFactory = services.2
            state = .ready
        } catch {
            homeModel = nil
            conversationsModel = nil
            conversationFactory = nil
            state = .recoveryRequired
        }
        return state
    }

    func requireRecovery() {
        state = .recoveryRequired
    }
}
