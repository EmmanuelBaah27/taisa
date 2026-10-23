import Foundation
import Testing
@testable import TaisaStorage

@Suite(.serialized) struct ActionQueryTests {
    @Test func collectionFiltersLifecycleParentDueWeekAndOriginWithStableOrdering() async throws {
        let fixture = try await ActionQueryFixture()
        defer { fixture.remove() }
        let goal = try await fixture.commands.createGoal(title: "Goal", detail: "", context: fixture.context(10))
        let milestone = try await fixture.commands.createMilestone(goalID: goal.id, title: "Milestone", targetAtMS: nil, context: fixture.context(20))
        let overdue = try await fixture.commands.createAction(goalID: goal.id, milestoneID: milestone.id, title: "Overdue", detail: "", dueDay: try ActionDueDay(validating: "2026-10-22"), context: fixture.context(30))
        let due = try await fixture.commands.createAction(goalID: goal.id, milestoneID: nil, title: "Due", detail: "", dueDay: try ActionDueDay(validating: "2026-10-23"), context: fixture.context(40))
        let undated = try await fixture.commands.createAction(goalID: nil, milestoneID: nil, title: "Undated", detail: "", dueDay: nil, context: fixture.context(50))
        _ = try await fixture.commands.dropAction(id: undated.id, context: fixture.context(60))
        let zone = try #require(TimeZone(identifier: "Africa/Accra"))
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let weekDate = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 23)))
        try await WeeklyWorkRepository(store: fixture.store).place(actionID: overdue.id, weekContaining: weekDate, plannedDay: nil, timeZone: zone, context: fixture.context(70))
        let week = try WeekCalendar(timeZone: zone).week(containing: weekDate)
        let weekStartMS = Int64((week.start.timeIntervalSince1970 * 1_000).rounded())

        let query = CareerWorkQuery(store: fixture.store)
        let allActive = try await query.actions(
            filter: .init(lifecycle: .active),
            localDay: try ActionDueDay(validating: "2026-10-23")
        )
        #expect(allActive.map(\.id) == [overdue.id, due.id])
        #expect(try await query.actions(filter: .init(lifecycle: .active, goalID: goal.id, milestoneID: milestone.id), localDay: try ActionDueDay(validating: "2026-10-23")).map(\.id) == [overdue.id])
        #expect(try await query.actions(filter: .init(lifecycle: .active, due: .overdue), localDay: try ActionDueDay(validating: "2026-10-23")).map(\.id) == [overdue.id])
        #expect(try await query.actions(filter: .init(lifecycle: .active, due: .due), localDay: try ActionDueDay(validating: "2026-10-23")).map(\.id) == [due.id])
        #expect(try await query.actions(filter: .init(lifecycle: .dropped, due: .noDueDay), localDay: try ActionDueDay(validating: "2026-10-23")).map(\.id) == [undated.id])
        #expect(try await query.actions(filter: .init(lifecycle: .active, weekStartMS: weekStartMS, origin: .manual), localDay: try ActionDueDay(validating: "2026-10-23")).map(\.id) == [overdue.id])
    }

    @Test func detailAndDuplicateCandidatesExposeCanonicalFactsWithoutSupersededEvidence() async throws {
        let fixture = try await ActionQueryFixture()
        defer { fixture.remove() }
        let goal = try await fixture.commands.createGoal(title: "Goal", detail: "", context: fixture.context(10))
        let action = try await fixture.commands.createAction(goalID: goal.id, milestoneID: nil, title: " Prepare Launch ", detail: "", dueDay: nil, context: fixture.context(20))
        let item = try await fixture.commands.addChecklistItem(actionID: action.id, title: "Share brief", context: fixture.context(30))
        let first = try await fixture.commands.completeAction(id: action.id, evidenceTitle: "First completion", context: fixture.context(40))
        _ = try await fixture.commands.undoMistakenCompletion(id: action.id, completionEventID: first.event.id, context: fixture.context(50))
        let second = try await fixture.commands.completeAction(id: action.id, evidenceTitle: "Final completion", context: fixture.context(60))

        let query = CareerWorkQuery(store: fixture.store)
        let detail = try #require(try await query.actionDetail(id: action.id))
        #expect(detail.goal?.id == goal.id)
        #expect(detail.checklist.map(\.id) == [item.id])
        #expect(detail.events.map(\.kind).contains(.completionCorrected))
        #expect(detail.currentEvidence.map(\.id) == [second.evidence.id])
        #expect(detail.supersededEvidence.map(\.id) == [first.evidence.id])

        let duplicateReview = try await query.duplicateReview(title: "prepare   launch")
        #expect(duplicateReview.candidates.map(\.id) == [action.id])
        #expect(duplicateReview.decisions == [.openExisting, .createSeparate])
    }
}

private struct ActionQueryFixture {
    let directory: URL
    let store: TaisaStore
    let commands: CareerWorkCommandRepository
    let deviceID = UUID().uuidString

    init() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: ActionQueryKeys())
        commands = CareerWorkCommandRepository(store: store)
    }

    func context(_ timestamp: Int64) -> MutationContext { .init(id: UUID().uuidString, deviceID: deviceID, timestamp: timestamp) }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private actor ActionQueryKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}
