import Observation
import TaisaStorage

@MainActor
@Observable
public final class CareerWorkModel {
    public private(set) var state: CareerWorkState
    public private(set) var route: CareerWorkRoute

    @ObservationIgnored private let client: CareerWorkClient
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var loadTask: Task<LoadOutcome, Never>?

    public init(client: CareerWorkClient, initialState: CareerWorkState = .idle, route: CareerWorkRoute = .overview) {
        self.client = client
        self.state = initialState
        self.route = route
    }

    public func load() async {
        generation += 1
        let active = generation
        let retained = state.snapshot
        loadTask?.cancel()
        state = retained.map { .content($0, isRefreshing: true, issue: nil) } ?? .loading
        let client = client
        let route = route
        let task = Task<LoadOutcome, Never> {
            do {
                async let overview = client.loadOverview()
                let detail: CareerGoalSnapshot?
                let action: ActionRecord?
                let evidence: EvidenceRecord?
                switch route {
                case let .goal(id):
                    detail = try await client.loadGoal(id); action = nil; evidence = nil
                case let .action(id):
                    detail = nil; action = try await client.loadAction(id); evidence = nil
                case let .evidence(id):
                    detail = nil; action = nil; evidence = try await client.loadEvidence(id)
                case .overview:
                    detail = nil; action = nil; evidence = nil
                }
                let snapshot = try await CareerWorkProductSnapshot(overview: overview, selectedGoal: detail, selectedAction: action, selectedEvidence: evidence)
                try Task.checkCancellation()
                return .success(snapshot)
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .failure(Self.issue(for: error))
            }
        }
        loadTask = task
        let outcome = await task.value
        guard generation == active else { return }
        loadTask = nil
        switch outcome {
        case let .success(snapshot): state = snapshot.isEmpty ? .empty : .content(snapshot, isRefreshing: false, issue: nil)
        case let .failure(issue): state = retained.map { .content($0, isRefreshing: false, issue: issue) } ?? .failure(issue)
        case .cancelled: state = retained.map { .content($0, isRefreshing: false, issue: nil) } ?? .idle
        }
    }

    public func retry() async { await load() }

    public func select(_ route: CareerWorkRoute) async {
        self.route = route
        await load()
    }

    public func createGoal(title: String, detail: String) async {
        await mutate {
            let goal = try await client.createGoal(title, detail)
            route = .goal(id: goal.id)
        }
    }

    public func updateSelectedGoal(title: String, detail: String) async {
        guard case let .goal(id) = route else { return }
        await mutate { try await client.updateGoal(id, title, detail) }
    }

    public func createMilestone(title: String, targetAtMS: Int64?) async {
        guard case let .goal(id) = route else { return }
        await mutate { _ = try await client.createMilestone(id, title, targetAtMS) }
    }

    public func createAction(title: String, detail: String, dueAtMS: Int64?) async {
        guard case let .goal(id) = route else { return }
        await mutate { _ = try await client.createAction(id, title, detail, dueAtMS) }
    }

    public func addEvidence(actionID: String?, title: String, detail: String, occurredAtMS: Int64) async {
        guard case let .goal(id) = route else { return }
        await mutate { _ = try await client.addEvidence(id, actionID, title, detail, occurredAtMS) }
    }

    public func transitionSelectedGoal(to status: GoalStatus) async {
        guard case let .goal(id) = route else { return }
        await mutate { try await client.transitionGoal(id, status) }
    }

    public func archiveSelectedGoal() async {
        guard case let .goal(id) = route else { return }
        await mutate { try await client.archiveGoal(id) }
    }

    public func restoreSelectedGoal() async {
        guard case let .goal(id) = route else { return }
        await mutate { try await client.restoreGoal(id) }
    }

    private func mutate(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            await load()
        } catch {
            let issue = Self.issue(for: error)
            state = state.snapshot.map { .content($0, isRefreshing: false, issue: issue) } ?? .failure(issue)
        }
    }

    private static func issue(for error: any Error) -> CareerWorkIssue {
        if error is CareerWorkProposalError { return .conflict }
        if error is CareerWorkContractError { return .invalidInput }
        guard let storage = error as? StorageError else { return .storageUnavailable }
        switch storage {
        case .missingKeyForExistingStore, .authenticationFailed, .integrityFailed, .schemaMismatch, .unsupportedMigration, .unsupportedSchemaVersion:
            return .recoveryRequired
        default:
            return .storageUnavailable
        }
    }
}

private enum LoadOutcome: Sendable {
    case success(CareerWorkProductSnapshot)
    case failure(CareerWorkIssue)
    case cancelled
}
