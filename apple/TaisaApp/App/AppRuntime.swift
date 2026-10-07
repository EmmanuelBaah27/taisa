import Observation
import TaisaHome
import TaisaStorage

@MainActor
@Observable
final class AppRuntime {
    struct Clients: Sendable {
        let home: HomeClient
        let insights: InsightsClient
    }

    enum State: Equatable {
        case startup
        case ready
        case recoveryRequired
    }

    private(set) var state: State = .startup
    private(set) var homeModel: HomeModel?
    private(set) var insightsModel: InsightsModel?
    @ObservationIgnored private let startOperation: @Sendable () async throws -> Clients

    init(start: @escaping @Sendable () async throws -> Clients) {
        startOperation = start
    }

    static func live() -> AppRuntime {
        AppRuntime {
            let backend = try PersonalRecoveryBackend.personal()
            let store = try await backend.openStore()
            return Clients(
                home: HomeClient.local(store: store, deviceID: await backend.deviceID()),
                insights: InsightsClient.local(store: store)
            )
        }
    }

    @discardableResult
    func start() async -> State {
        guard state == .startup else { return state }
        do {
            let clients = try await startOperation()
            homeModel = HomeModel(client: clients.home)
            insightsModel = InsightsModel(client: clients.insights)
            state = .ready
        } catch {
            homeModel = nil
            insightsModel = nil
            state = .recoveryRequired
        }
        return state
    }

    func requireRecovery() {
        state = .recoveryRequired
    }
}
