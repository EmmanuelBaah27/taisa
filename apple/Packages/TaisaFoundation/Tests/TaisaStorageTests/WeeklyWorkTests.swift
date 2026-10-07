import Foundation
import GRDB
import Testing
@testable import TaisaStorage

@Suite(.serialized) struct WeeklyWorkTests {
    @Test func unfinishedPriorWeekWorkWaitsForDeliberateMove() async throws {
        let fixture = try await WeeklyFixture()
        defer { fixture.remove() }
        let action = try await fixture.createAction(title: "Prepare review")
        let accra = try #require(TimeZone(identifier: "Africa/Accra"))
        let previousWeek = fixture.date(2026, 9, 28, hour: 9, timeZone: accra)
        let currentWeek = fixture.date(2026, 10, 5, hour: 9, timeZone: accra)

        try await fixture.repository.place(actionID: action.id, weekContaining: previousWeek, plannedDay: nil, timeZone: accra, context: fixture.context(10))
        let beforeMove = try await fixture.query.snapshot(weekContaining: currentWeek, timeZone: accra)
        #expect(beforeMove.items.isEmpty)
        #expect(beforeMove.unresolvedPriorWeekCount == 1)

        try await fixture.repository.move(actionID: action.id, weekContaining: currentWeek, plannedDay: currentWeek, timeZone: accra, context: fixture.context(20))
        let afterMove = try await fixture.query.snapshot(weekContaining: currentWeek, timeZone: accra)
        #expect(afterMove.items.map(\.action.title) == ["Prepare review"])
        #expect(afterMove.unresolvedPriorWeekCount == 0)
        #expect(try await fixture.store.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM work_events WHERE action_id = ?", arguments: [action.id]) } == 2)
    }

    @Test func duplicatePlacementIsIdempotentAndOrderingIsDeterministic() async throws {
        let fixture = try await WeeklyFixture()
        defer { fixture.remove() }
        let accra = try #require(TimeZone(identifier: "Africa/Accra"))
        let week = fixture.date(2026, 10, 5, hour: 9, timeZone: accra)
        let later = try await fixture.createAction(title: "Later", timestamp: 2)
        let earlier = try await fixture.createAction(title: "Earlier", timestamp: 1)
        let tuesday = fixture.date(2026, 10, 6, hour: 14, timeZone: accra)
        let friday = fixture.date(2026, 10, 9, hour: 8, timeZone: accra)

        try await fixture.repository.place(actionID: later.id, weekContaining: week, plannedDay: friday, timeZone: accra, context: fixture.context(10))
        try await fixture.repository.place(actionID: earlier.id, weekContaining: week, plannedDay: tuesday, timeZone: accra, context: fixture.context(11))
        try await fixture.repository.place(actionID: earlier.id, weekContaining: week, plannedDay: tuesday, timeZone: accra, context: fixture.context(12))

        let snapshot = try await fixture.query.snapshot(weekContaining: week, timeZone: accra)
        #expect(snapshot.items.map(\.action.title) == ["Earlier", "Later"])
        #expect(try await fixture.store.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM weekly_placements") } == 2)
        #expect(try await fixture.store.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM work_events") } == 2)
    }

    @Test func completionRemovesWorkAndUndoRestoresIt() async throws {
        let fixture = try await WeeklyFixture()
        defer { fixture.remove() }
        let accra = try #require(TimeZone(identifier: "Africa/Accra"))
        let week = fixture.date(2026, 10, 5, hour: 9, timeZone: accra)
        let action = try await fixture.createAction(title: "Finish brief")
        try await fixture.repository.place(actionID: action.id, weekContaining: week, plannedDay: nil, timeZone: accra, context: fixture.context(10))

        let undo = try await fixture.repository.complete(actionID: action.id, context: fixture.context(20))
        #expect(try await fixture.query.snapshot(weekContaining: week, timeZone: accra).items.isEmpty)
        try await fixture.repository.restore(undo, context: fixture.context(30))
        #expect(try await fixture.query.snapshot(weekContaining: week, timeZone: accra).items.map(\.action.title) == ["Finish brief"])
    }

    @Test func deletedActionCannotRemainVisibleOrNeedPriorWeekReview() async throws {
        let fixture = try await WeeklyFixture()
        defer { fixture.remove() }
        let accra = try #require(TimeZone(identifier: "Africa/Accra"))
        let previousWeek = fixture.date(2026, 9, 28, hour: 9, timeZone: accra)
        let currentWeek = fixture.date(2026, 10, 5, hour: 9, timeZone: accra)
        let action = try await fixture.createAction(title: "Remove me")
        try await fixture.repository.place(actionID: action.id, weekContaining: previousWeek, plannedDay: nil, timeZone: accra, context: fixture.context(10))

        try await ActionRepository(store: fixture.store).delete(id: action.id, context: fixture.context(20))

        let snapshot = try await fixture.query.snapshot(weekContaining: currentWeek, timeZone: accra)
        #expect(snapshot.items.isEmpty)
        #expect(snapshot.unresolvedPriorWeekCount == 0)
    }
}

private struct WeeklyFixture {
    let directory: URL
    let store: TaisaStore
    let repository: WeeklyWorkRepository
    let query: WeeklyWorkQuery
    let deviceID = UUID().uuidString

    init() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: WeeklyKeys())
        repository = WeeklyWorkRepository(store: store)
        query = WeeklyWorkQuery(store: store)
    }
    func createAction(title: String, timestamp: Int64 = 1) async throws -> ActionRecord {
        let action = ActionRecord(id: UUID().uuidString, goalID: nil, title: title, detail: "", status: "open", dueAtMS: nil, createdAtMS: timestamp, updatedAtMS: timestamp)
        try await ActionRepository(store: store).create(action, context: context(timestamp))
        return action
    }
    func context(_ timestamp: Int64) -> MutationContext { .init(id: UUID().uuidString, deviceID: deviceID, timestamp: timestamp) }
    func date(_ year: Int, _ month: Int, _ day: Int, hour: Int, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private actor WeeklyKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}
