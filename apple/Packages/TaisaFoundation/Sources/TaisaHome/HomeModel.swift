import Foundation
import Observation
import TaisaStorage

@MainActor
@Observable
public final class HomeModel {
    public private(set) var state: HomeState
    public private(set) var completionUndoToken: WeeklyWorkUndoToken?
    public var canUndoCompletion: Bool { completionUndoToken != nil }

    @ObservationIgnored private let client: HomeClient
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var mutationGeneration = 0
    @ObservationIgnored private var loadTask: Task<LoadOutcome, Never>?

    public init(client: HomeClient, initialState: HomeState = .idle) {
        self.client = client
        state = initialState
    }

    public func load() async {
        generation += 1
        let activeGeneration = generation
        let retainedSnapshot = state.snapshot

        loadTask?.cancel()
        if let retainedSnapshot {
            state = .content(retainedSnapshot, isRefreshing: true, issue: nil)
        } else {
            state = .loading
        }

        let client = client
        let task = Task<LoadOutcome, Never> {
            do {
                let snapshot = try await client.load()
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
        guard generation == activeGeneration else { return }
        loadTask = nil

        switch outcome {
        case let .success(snapshot):
            state = snapshot.isEmpty ? .empty : .content(snapshot, isRefreshing: false, issue: nil)
        case let .failure(issue):
            if let retainedSnapshot {
                state = .content(retainedSnapshot, isRefreshing: false, issue: issue)
            } else {
                state = .failure(issue)
            }
        case .cancelled:
            if let retainedSnapshot {
                state = .content(retainedSnapshot, isRefreshing: false, issue: nil)
            } else {
                state = .idle
            }
        }
    }

    public func complete(actionID: String) async {
        mutationGeneration += 1
        let active = mutationGeneration
        do {
            let token = try await client.complete(actionID)
            guard mutationGeneration == active else { return }
            completionUndoToken = token
            await load()
        } catch {
            guard mutationGeneration == active else { return }
            publishMutationFailure(error)
        }
    }

    public func undoCompletion() async {
        guard let token = completionUndoToken else { return }
        mutationGeneration += 1
        let active = mutationGeneration
        do {
            try await client.restore(token)
            guard mutationGeneration == active else { return }
            completionUndoToken = nil
            await load()
        } catch {
            guard mutationGeneration == active else { return }
            publishMutationFailure(error)
        }
    }

    public func place(actionID: String, weekContaining: Date, plannedDay: Date?) async {
        await mutate { try await client.place(actionID, weekContaining, plannedDay) }
    }

    public func move(actionID: String, weekContaining: Date, plannedDay: Date?) async {
        await mutate { try await client.move(actionID, weekContaining, plannedDay) }
    }

    private func mutate(_ operation: () async throws -> Void) async {
        mutationGeneration += 1
        let active = mutationGeneration
        do {
            try await operation()
            guard mutationGeneration == active else { return }
            await load()
        } catch {
            guard mutationGeneration == active else { return }
            publishMutationFailure(error)
        }
    }

    private func publishMutationFailure(_ error: any Error) {
        let issue = Self.issue(for: error)
        if let snapshot = state.snapshot { state = .content(snapshot, isRefreshing: false, issue: issue) }
        else { state = .failure(issue) }
    }

    private static func issue(for error: any Error) -> HomeIssue {
        guard let storageError = error as? StorageError else {
            return .storageUnavailable
        }
        switch storageError {
        case .missingKeyForExistingStore, .authenticationFailed, .integrityFailed,
             .schemaMismatch, .unsupportedMigration, .unsupportedSchemaVersion:
            return .recoveryRequired
        case .invalidKeyLength, .randomGenerationFailed, .keychainFailure,
             .openFailed, .cipherUnavailable, .configurationFailed, .migrationFailed:
            return .storageUnavailable
        }
    }
}

private enum LoadOutcome: Sendable {
    case success(HomeSnapshot)
    case failure(HomeIssue)
    case cancelled
}

private extension HomeState {
    var snapshot: HomeSnapshot? {
        guard case let .content(snapshot, _, _) = self else { return nil }
        return snapshot
    }
}
