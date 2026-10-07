import Foundation
import Testing
@testable import TaisaStorage

@Suite(.serialized) struct CombinedHomeRepositoryTests {
    @Test func durableCombinedHomeRecordsRoundTripThroughRepositories() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(
            at: directory.appendingPathComponent("store.sqlite"),
            keyStore: CombinedHomeRepositoryKeys()
        )
        let deviceID = UUID().uuidString
        let actionID = UUID().uuidString
        try await ActionRepository(store: store).create(
            ActionRecord(id: actionID, goalID: nil, title: "Plan week", detail: "", status: "open", dueAtMS: nil, createdAtMS: 1, updatedAtMS: 1),
            context: MutationContext(id: UUID().uuidString, deviceID: deviceID, timestamp: 1)
        )

        let placement = WeeklyPlacementRecord(id: UUID().uuidString, actionID: actionID, weekStartMS: 100, plannedDayMS: 200, createdAtMS: 2, updatedAtMS: 2)
        let event = WorkEventRecord(id: UUID().uuidString, actionID: actionID, kind: .placed, fromWeekStartMS: nil, toWeekStartMS: 100, sourceType: "user", sourceID: nil, occurredAtMS: 2)
        let insight = InsightRecord(id: UUID().uuidString, body: "Focus time works best early.", status: .confirmed, isTimeSensitive: true, homeEligibleUntilMS: 1_000, createdAtMS: 3, updatedAtMS: 3)
        let source = InsightSourceRecord(id: UUID().uuidString, insightID: insight.id, sourceType: "conversation", sourceID: UUID().uuidString, excerpt: "Morning focus", createdAtMS: 3)
        let revision = InsightRevisionRecord(id: UUID().uuidString, insightID: insight.id, proposedBody: "Protect early focus time.", status: .proposed, sourceType: "user", sourceID: nil, createdAtMS: 4, resolvedAtMS: nil)

        try await WeeklyPlacementRepository(store: store).create(placement, context: .init(id: UUID().uuidString, deviceID: deviceID, timestamp: 2))
        try await WorkEventRepository(store: store).create(event, context: .init(id: UUID().uuidString, deviceID: deviceID, timestamp: 2))
        try await InsightRepository(store: store).create(insight, context: .init(id: UUID().uuidString, deviceID: deviceID, timestamp: 3))
        try await InsightSourceRepository(store: store).create(source, context: .init(id: UUID().uuidString, deviceID: deviceID, timestamp: 3))
        try await InsightRevisionRepository(store: store).create(revision, context: .init(id: UUID().uuidString, deviceID: deviceID, timestamp: 4))

        #expect(try await WeeklyPlacementRepository(store: store).get(id: placement.id) == placement)
        #expect(try await WorkEventRepository(store: store).get(id: event.id) == event)
        #expect(try await InsightRepository(store: store).get(id: insight.id) == insight)
        #expect(try await InsightSourceRepository(store: store).get(id: source.id) == source)
        #expect(try await InsightRevisionRepository(store: store).get(id: revision.id) == revision)
    }
}

private actor CombinedHomeRepositoryKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}
