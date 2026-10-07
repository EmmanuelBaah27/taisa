import Foundation
import Observation
import TaisaStorage

@MainActor
@Observable
public final class HomeModel {
    public private(set) var state: HomeState = .idle

    @ObservationIgnored private let client: HomeClient
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var loadTask: Task<LoadOutcome, Never>?

    public init(client: HomeClient) {
        self.client = client
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
