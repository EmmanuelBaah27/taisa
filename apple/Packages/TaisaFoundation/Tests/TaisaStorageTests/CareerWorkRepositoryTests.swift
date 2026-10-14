import Foundation
import GRDB
import Testing
@testable import TaisaStorage


@Suite(.serialized) struct CareerWorkRepositoryTests {
    @Test func acceptedWorkPersistsWithInspectableProgressAndProvenance() async throws {
        let fixture = try await CareerWorkFixture()
        defer { fixture.remove() }

        let goal = try await fixture.commands.createGoal(title: "  Lead the launch  ", detail: "Own delivery", context: fixture.context(10))
        let milestone = try await fixture.commands.createMilestone(goalID: goal.id, title: "Ship beta", targetAtMS: 500, context: fixture.context(20))
        let action = try await fixture.commands.createAction(goalID: goal.id, title: "Write rollout", detail: "", dueAtMS: 400, context: fixture.context(30))
        let evidence = try await fixture.commands.addEvidence(goalID: goal.id, actionID: action.id, title: "Beta accepted", detail: "", occurredAtMS: 35, origin: .user, originID: nil, context: fixture.context(40))

        _ = try await fixture.commands.transitionMilestone(id: milestone.id, to: .completed, source: .user, context: fixture.context(50))
        _ = try await fixture.commands.transitionAction(id: action.id, to: .completed, source: .user, context: fixture.context(60))

        let snapshot = try #require(try await fixture.query.goal(id: goal.id))
        #expect(snapshot.goal.title == "Lead the launch")
        #expect(snapshot.milestones.map(\.status) == ["completed"])
        #expect(snapshot.actions.map(\.status) == ["completed"])
        #expect(snapshot.evidence.map(\.id) == [evidence.id])
        #expect(snapshot.progress.summary == "1 of 1 milestones and 1 of 1 actions completed; 1 evidence item recorded.")
        #expect(snapshot.provenance.first?.origin == .user)
    }

    @Test func invalidLifecycleIsRejectedWithoutPartialHistory() async throws {
        let fixture = try await CareerWorkFixture()
        defer { fixture.remove() }
        let goal = try await fixture.commands.createGoal(title: "Goal", detail: "", context: fixture.context(10))

        await #expect(throws: CareerWorkContractError.invalidTransition) {
            try await fixture.commands.transitionGoal(id: goal.id, to: .active, source: .user, context: fixture.context(20))
        }
        #expect(try await fixture.store.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM career_work_events WHERE entity_id = ?", arguments: [goal.id])
        } == 1)
    }

    @Test func goalPauseResumeCompleteReopenAndArchiveRemainSeparate() async throws {
        let fixture = try await CareerWorkFixture()
        defer { fixture.remove() }
        let goal = try await fixture.commands.createGoal(title: "Goal", detail: "", context: fixture.context(10))

        _ = try await fixture.commands.transitionGoal(id: goal.id, to: .paused, source: .user, context: fixture.context(20))
        _ = try await fixture.commands.transitionGoal(id: goal.id, to: .active, source: .user, context: fixture.context(30))
        _ = try await fixture.commands.transitionGoal(id: goal.id, to: .completed, source: .user, context: fixture.context(40))
        _ = try await fixture.commands.transitionGoal(id: goal.id, to: .active, source: .undo, context: fixture.context(50))
        try await fixture.commands.archiveGoal(id: goal.id, context: fixture.context(60))

        #expect(try await fixture.query.overview().active.isEmpty)
        #expect(try await fixture.query.overview().archived.map(\.id) == [goal.id])
        try await fixture.commands.restoreGoal(id: goal.id, context: fixture.context(70))
        #expect(try await fixture.query.overview().active.map(\.id) == [goal.id])
    }

    @Test func evidenceCorrectionPreservesOriginalAndSupersession() async throws {
        let fixture = try await CareerWorkFixture()
        defer { fixture.remove() }
        let goal = try await fixture.commands.createGoal(title: "Goal", detail: "", context: fixture.context(10))
        let original = try await fixture.commands.addEvidence(goalID: goal.id, actionID: nil, title: "Draft", detail: "", occurredAtMS: 10, origin: .conversation, originID: UUID().uuidString, context: fixture.context(20))
        let corrected = try await fixture.commands.correctEvidence(id: original.id, title: "Final", detail: "Confirmed", occurredAtMS: 15, origin: .user, context: fixture.context(30))

        let snapshot = try #require(try await fixture.query.goal(id: goal.id))
        #expect(Set(snapshot.evidence.map(\.id)) == Set([original.id, corrected.id]))
        #expect(snapshot.provenance.first(where: { $0.evidenceID == corrected.id })?.supersedesEvidenceID == original.id)
    }
}

private struct CareerWorkFixture {
    let directory: URL
    let store: TaisaStore
    let commands: CareerWorkCommandRepository
    let query: CareerWorkQuery
    let deviceID = UUID().uuidString

    init() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: CareerWorkKeys())
        commands = CareerWorkCommandRepository(store: store)
        query = CareerWorkQuery(store: store)
    }

    func context(_ timestamp: Int64) -> MutationContext { .init(id: UUID().uuidString, deviceID: deviceID, timestamp: timestamp) }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private actor CareerWorkKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}
