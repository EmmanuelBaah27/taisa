import Foundation
import TaisaStorage

public struct HomeClient: Sendable {
    public var load: @Sendable () async throws -> HomeSnapshot
    public var complete: @Sendable (String, String) async throws -> ActionCompletionResult
    public var correctCompletion: @Sendable (String, String) async throws -> ActionRecord
    public var drop: @Sendable (String) async throws -> ActionRecord
    public var reopen: @Sendable (String) async throws -> ActionRecord
    public var delete: @Sendable (String) async throws -> Void
    public var restoreDeleted: @Sendable (String) async throws -> ActionRecord
    public var place: @Sendable (String, Date, Date?) async throws -> Void
    public var move: @Sendable (String, Date, Date?) async throws -> Void

    public init(
        load: @escaping @Sendable () async throws -> HomeSnapshot,
        complete: @escaping @Sendable (String, String) async throws -> ActionCompletionResult = { _, _ in throw HomeClientError.mutationUnavailable },
        correctCompletion: @escaping @Sendable (String, String) async throws -> ActionRecord = { _, _ in throw HomeClientError.mutationUnavailable },
        drop: @escaping @Sendable (String) async throws -> ActionRecord = { _ in throw HomeClientError.mutationUnavailable },
        reopen: @escaping @Sendable (String) async throws -> ActionRecord = { _ in throw HomeClientError.mutationUnavailable },
        delete: @escaping @Sendable (String) async throws -> Void = { _ in throw HomeClientError.mutationUnavailable },
        restoreDeleted: @escaping @Sendable (String) async throws -> ActionRecord = { _ in throw HomeClientError.mutationUnavailable },
        place: @escaping @Sendable (String, Date, Date?) async throws -> Void = { _, _, _ in throw HomeClientError.mutationUnavailable },
        move: @escaping @Sendable (String, Date, Date?) async throws -> Void = { _, _, _ in throw HomeClientError.mutationUnavailable }
    ) {
        self.load = load
        self.complete = complete
        self.correctCompletion = correctCompletion
        self.drop = drop
        self.reopen = reopen
        self.delete = delete
        self.restoreDeleted = restoreDeleted
        self.place = place
        self.move = move
    }
}

public enum HomeClientError: Error, Sendable { case mutationUnavailable }

public extension HomeClient {
    static func local(
        store: TaisaStore,
        deviceID: String,
        now: @escaping @Sendable () -> Date = { Date() },
        timeZone: @escaping @Sendable () -> TimeZone = { .current }
    ) -> HomeClient {
        let weekly = WeeklyWorkRepository(store: store)
        let actions = CareerWorkCommandRepository(store: store)
        let context: @Sendable () -> MutationContext = {
            MutationContext(id: UUID().uuidString, deviceID: deviceID, timestamp: Int64((now().timeIntervalSince1970 * 1_000).rounded()))
        }
        return HomeClient(
            load: {
                let date = now()
                return try await HomeQuery(store: store).load(weekContaining: date, timeZone: timeZone())
            },
            complete: { try await actions.completeAction(id: $0, evidenceTitle: $1, context: context()) },
            correctCompletion: { try await actions.undoMistakenCompletion(id: $0, completionEventID: $1, context: context()) },
            drop: { try await actions.dropAction(id: $0, context: context()) },
            reopen: { try await actions.reopenAction(id: $0, context: context()) },
            delete: { try await actions.deleteAction(id: $0, context: context()) },
            restoreDeleted: { try await actions.restoreAction(id: $0, context: context()) },
            place: { try await weekly.place(actionID: $0, weekContaining: $1, plannedDay: $2, timeZone: timeZone(), context: context()) },
            move: { try await weekly.move(actionID: $0, weekContaining: $1, plannedDay: $2, timeZone: timeZone(), context: context()) }
        )
    }
}
