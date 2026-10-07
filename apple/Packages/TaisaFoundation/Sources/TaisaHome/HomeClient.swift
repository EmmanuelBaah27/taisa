import Foundation
import TaisaStorage

public struct HomeClient: Sendable {
    public var load: @Sendable () async throws -> HomeSnapshot
    public var complete: @Sendable (String) async throws -> WeeklyWorkUndoToken
    public var restore: @Sendable (WeeklyWorkUndoToken) async throws -> Void
    public var place: @Sendable (String, Date, Date?) async throws -> Void
    public var move: @Sendable (String, Date, Date?) async throws -> Void

    public init(
        load: @escaping @Sendable () async throws -> HomeSnapshot,
        complete: @escaping @Sendable (String) async throws -> WeeklyWorkUndoToken = { _ in throw HomeClientError.mutationUnavailable },
        restore: @escaping @Sendable (WeeklyWorkUndoToken) async throws -> Void = { _ in throw HomeClientError.mutationUnavailable },
        place: @escaping @Sendable (String, Date, Date?) async throws -> Void = { _, _, _ in throw HomeClientError.mutationUnavailable },
        move: @escaping @Sendable (String, Date, Date?) async throws -> Void = { _, _, _ in throw HomeClientError.mutationUnavailable }
    ) {
        self.load = load
        self.complete = complete
        self.restore = restore
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
        let context: @Sendable () -> MutationContext = {
            MutationContext(id: UUID().uuidString, deviceID: deviceID, timestamp: Int64((now().timeIntervalSince1970 * 1_000).rounded()))
        }
        return HomeClient(
            load: {
                let date = now()
                return try await HomeQuery(store: store).load(weekContaining: date, timeZone: timeZone())
            },
            complete: { try await weekly.complete(actionID: $0, context: context()) },
            restore: { try await weekly.restore($0, context: context()) },
            place: { try await weekly.place(actionID: $0, weekContaining: $1, plannedDay: $2, timeZone: timeZone(), context: context()) },
            move: { try await weekly.move(actionID: $0, weekContaining: $1, plannedDay: $2, timeZone: timeZone(), context: context()) }
        )
    }
}
