import Observation
import TaisaHome
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
    @ObservationIgnored private let startOperation: @Sendable () async throws -> HomeClient

    init(start: @escaping @Sendable () async throws -> HomeClient) {
        startOperation = start
    }

    static func live() -> AppRuntime {
        AppRuntime {
            let backend = try PersonalRecoveryBackend.personal()
            let store = try await backend.openStore()
            return HomeClient { try await HomeQuery(store: store).load() }
        }
    }

    @discardableResult
    func start() async -> State {
        guard state == .startup else { return state }
        do {
            homeModel = HomeModel(client: try await startOperation())
            state = .ready
        } catch {
            homeModel = nil
            state = .recoveryRequired
        }
        return state
    }

    func requireRecovery() {
        state = .recoveryRequired
    }
}
