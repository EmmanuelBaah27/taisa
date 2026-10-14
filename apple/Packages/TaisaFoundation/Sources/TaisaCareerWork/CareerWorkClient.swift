import Foundation
import TaisaStorage

public enum CareerWorkClientError: Error, Sendable { case mutationUnavailable }

public struct CareerWorkClient: Sendable {
    public var loadOverview: @Sendable () async throws -> CareerWorkOverview
    public var loadGoal: @Sendable (String) async throws -> CareerGoalSnapshot?
    public var createGoal: @Sendable (String, String) async throws -> GoalRecord
    public var updateGoal: @Sendable (String, String, String) async throws -> Void
    public var transitionGoal: @Sendable (String, GoalStatus) async throws -> Void
    public var archiveGoal: @Sendable (String) async throws -> Void
    public var restoreGoal: @Sendable (String) async throws -> Void

    public init(
        loadOverview: @escaping @Sendable () async throws -> CareerWorkOverview,
        loadGoal: @escaping @Sendable (String) async throws -> CareerGoalSnapshot? = { _ in nil },
        createGoal: @escaping @Sendable (String, String) async throws -> GoalRecord = { _, _ in throw CareerWorkClientError.mutationUnavailable },
        updateGoal: @escaping @Sendable (String, String, String) async throws -> Void = { _, _, _ in throw CareerWorkClientError.mutationUnavailable },
        transitionGoal: @escaping @Sendable (String, GoalStatus) async throws -> Void = { _, _ in throw CareerWorkClientError.mutationUnavailable },
        archiveGoal: @escaping @Sendable (String) async throws -> Void = { _ in throw CareerWorkClientError.mutationUnavailable },
        restoreGoal: @escaping @Sendable (String) async throws -> Void = { _ in throw CareerWorkClientError.mutationUnavailable }
    ) {
        self.loadOverview = loadOverview
        self.loadGoal = loadGoal
        self.createGoal = createGoal
        self.updateGoal = updateGoal
        self.transitionGoal = transitionGoal
        self.archiveGoal = archiveGoal
        self.restoreGoal = restoreGoal
    }
}

public extension CareerWorkClient {
    static func local(store: TaisaStore, deviceID: String, nowMS: @escaping @Sendable () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }) -> Self {
        let query = CareerWorkQuery(store: store)
        let commands = CareerWorkCommandRepository(store: store)
        let context: @Sendable () -> MutationContext = { .init(id: UUID().uuidString, deviceID: deviceID, timestamp: nowMS()) }
        return .init(
            loadOverview: { try await query.overview() },
            loadGoal: { try await query.goal(id: $0) },
            createGoal: { try await commands.createGoal(title: $0, detail: $1, context: context()) },
            updateGoal: { try await commands.updateGoal(id: $0, title: $1, detail: $2, context: context()) },
            transitionGoal: { _ = try await commands.transitionGoal(id: $0, to: $1, source: .user, context: context()) },
            archiveGoal: { try await commands.archiveGoal(id: $0, context: context()) },
            restoreGoal: { try await commands.restoreGoal(id: $0, context: context()) }
        )
    }
}
