import Foundation
import GRDB
import Testing
@testable import TaisaStorage

private actor HomeQueryKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}

@Suite(.serialized) struct HomeQueryTests {
    @Test func returnsBoundedDeterministicallyOrderedVisibleRecords() async throws {
        let fixture = try await makeStore()
        defer { fixture.cleanup() }
        let ids = (1...8).map { _ in UUID().uuidString }.sorted()
        try await fixture.store.write { db in
            for (index, id) in ids.enumerated() {
                try db.execute(
                    sql: "INSERT INTO conversations (id, title, created_at_ms, updated_at_ms) VALUES (?, ?, ?, ?)",
                    arguments: [id, "Conversation \(index)", 100, index < 2 ? 500 : 500 - index]
                )
            }
            try db.execute(sql: "INSERT INTO goals VALUES (?, 'Active newest', '', 'active', 100, 300)", arguments: [ids[0]])
            try db.execute(sql: "INSERT INTO goals VALUES (?, 'Active tie', '', 'active', 100, 300)", arguments: [ids[1]])
            try db.execute(sql: "INSERT INTO goals VALUES (?, 'Completed', '', 'completed', 100, 400)", arguments: [ids[2]])
            try db.execute(sql: "INSERT INTO actions VALUES (?, NULL, 'Due first', '', 'open', 200, 100, 100)", arguments: [ids[3]])
            try db.execute(sql: "INSERT INTO actions VALUES (?, NULL, 'Due second', '', 'open', 300, 100, 100)", arguments: [ids[4]])
            try db.execute(sql: "INSERT INTO actions VALUES (?, NULL, 'Undated', '', 'open', NULL, 100, 900)", arguments: [ids[5]])
            try db.execute(sql: "INSERT INTO actions VALUES (?, NULL, 'Completed', '', 'completed', 100, 100, 100)", arguments: [ids[6]])
            try db.execute(sql: "INSERT INTO tombstones VALUES (?, 'conversation', ?, ?, 999)", arguments: [UUID().uuidString, ids[0], UUID().uuidString])
        }

        let snapshot = try await HomeQuery(store: fixture.store).load(
            limits: HomeLimits(conversations: 3, goals: 5, actions: 5)
        )

        #expect(snapshot.conversations.count == 3)
        #expect(!snapshot.conversations.map(\.id).contains(ids[0]))
        #expect(snapshot.goals.map(\.status) == ["active", "active"])
        #expect(snapshot.goals.map(\.id) == [ids[0], ids[1]])
        #expect(snapshot.actions.map(\.title) == ["Due first", "Due second", "Undated"])
        #expect(!snapshot.isEmpty)
    }

    @Test func emptyStoreReturnsEmptySnapshot() async throws {
        let fixture = try await makeStore()
        defer { fixture.cleanup() }
        #expect(try await HomeQuery(store: fixture.store).load().isEmpty)
    }

    @Test func combinedSnapshotIncludesWeeklyWorkAndOnlyGroundedLeadInsight() async throws {
        let fixture = try await makeStore()
        defer { fixture.cleanup() }
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        let currentWeek = Date(timeIntervalSince1970: 1_782_086_400) // 2026-06-22 Monday UTC
        let priorWeek = Date(timeIntervalSince1970: 1_781_481_600)
        let deviceID = UUID().uuidString
        let current = ActionRecord(id: UUID().uuidString, goalID: nil, title: "Current", detail: "", status: "open", dueAtMS: nil, createdAtMS: 1, updatedAtMS: 1)
        let unresolved = ActionRecord(id: UUID().uuidString, goalID: nil, title: "Prior", detail: "", status: "open", dueAtMS: nil, createdAtMS: 2, updatedAtMS: 2)
        for action in [current, unresolved] {
            try await ActionRepository(store: fixture.store).create(action, context: .init(id: UUID().uuidString, deviceID: deviceID, timestamp: action.createdAtMS))
        }
        let weekly = WeeklyWorkRepository(store: fixture.store)
        try await weekly.place(actionID: current.id, weekContaining: currentWeek, plannedDay: nil, timeZone: timeZone, context: .init(id: UUID().uuidString, deviceID: deviceID, timestamp: 3))
        try await weekly.place(actionID: unresolved.id, weekContaining: priorWeek, plannedDay: nil, timeZone: timeZone, context: .init(id: UUID().uuidString, deviceID: deviceID, timestamp: 4))
        let conversation = ConversationRecord(id: UUID().uuidString, title: "Grounding", createdAtMS: 5, updatedAtMS: 5)
        try await ConversationRepository(store: fixture.store).create(conversation, context: .init(id: UUID().uuidString, deviceID: deviceID, timestamp: 5))
        let insights = InsightCommandRepository(store: fixture.store)
        let proposal = try await insights.propose(body: "Lead", sourceType: "conversation", sourceID: conversation.id, context: .init(id: UUID().uuidString, deviceID: deviceID, timestamp: 6))
        let lead = try await insights.confirm(proposalID: proposal.id, editedBody: nil, isTimeSensitive: true, homeEligibleUntilMS: 2_000_000_000_000, context: .init(id: UUID().uuidString, deviceID: deviceID, timestamp: 7))

        let snapshot = try await HomeQuery(store: fixture.store).load(weekContaining: currentWeek, timeZone: timeZone)

        #expect(snapshot.thisWeek.map(\.action.id) == [current.id])
        #expect(snapshot.unresolvedPriorWeekCount == 1)
        #expect(snapshot.leadInsight == lead)
        #expect(snapshot.hasConfirmedInsightHistory)
    }

    @Test(arguments: [
        HomeLimits(conversations: 0, goals: 1, actions: 1),
        HomeLimits(conversations: 1, goals: -1, actions: 1),
    ])
    func rejectsNonPositiveLimits(_ limits: HomeLimits) async throws {
        let fixture = try await makeStore()
        defer { fixture.cleanup() }
        await #expect(throws: HomeQueryError.invalidLimit) {
            try await HomeQuery(store: fixture.store).load(limits: limits)
        }
    }

    private func makeStore() async throws -> (store: TaisaStore, cleanup: () -> Void) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: HomeQueryKeys())
        return (store, { try? FileManager.default.removeItem(at: directory) })
    }
}
