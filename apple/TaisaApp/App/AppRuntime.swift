import Observation
import TaisaHome
import TaisaConversations
import TaisaStorage

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
    let primaryShellModel: PrimaryAppShellModel
    @ObservationIgnored private let startOperation: @Sendable () async throws -> (HomeClient, ConversationsClient)

    init(
        primaryShellModel: PrimaryAppShellModel = PrimaryAppShellModel(),
        start: @escaping @Sendable () async throws -> HomeClient
    ) {
        self.primaryShellModel = primaryShellModel
        startOperation = {
            (try await start(), ConversationsClient(load: { ConversationIndexSnapshot(drafts: [], conversations: []) }))
        }
    }

    private init(
        primaryShellModel: PrimaryAppShellModel = PrimaryAppShellModel(),
        startServices: @escaping @Sendable () async throws -> (HomeClient, ConversationsClient)
    ) {
        self.primaryShellModel = primaryShellModel
        startOperation = startServices
    }

    static func live() -> AppRuntime {
        AppRuntime(startServices: {
            let backend = try PersonalRecoveryBackend.personal()
            let store = try await backend.openStore()
            return (
                HomeClient { try await HomeQuery(store: store).load() },
                ConversationsClient.local(store: store)
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
            state = .ready
        } catch {
            homeModel = nil
            conversationsModel = nil
            state = .recoveryRequired
        }
        return state
    }

    func requireRecovery() {
        state = .recoveryRequired
    }
}
