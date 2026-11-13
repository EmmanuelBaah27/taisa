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

    @Test func canonicalActionCreationValidatesMilestoneGoalAndSupportsStandalone() async throws {
        let fixture = try await CareerWorkFixture()
        defer { fixture.remove() }
        let firstGoal = try await fixture.commands.createGoal(title: "First", detail: "", context: fixture.context(10))
        let secondGoal = try await fixture.commands.createGoal(title: "Second", detail: "", context: fixture.context(20))
        let milestone = try await fixture.commands.createMilestone(goalID: firstGoal.id, title: "Milestone", targetAtMS: nil, context: fixture.context(30))

        let related = try await fixture.commands.createAction(
            goalID: firstGoal.id,
            milestoneID: milestone.id,
            title: "Related",
            detail: "",
            dueDay: try ActionDueDay(validating: "2026-10-23"),
            context: fixture.context(40)
        )
        let standalone = try await fixture.commands.createAction(
            goalID: nil,
            milestoneID: nil,
            title: "Standalone",
            detail: "",
            dueDay: nil,
            context: fixture.context(50)
        )

        #expect(related.goalID == firstGoal.id)
        #expect(related.milestoneID == milestone.id)
        #expect(related.dueDay?.rawValue == "2026-10-23")
        #expect(related.status == "active")
        let completed = try await fixture.commands.transitionAction(id: related.id, to: .completed, source: .user, context: fixture.context(41))
        #expect(completed.milestoneID == milestone.id)
        #expect(completed.dueDay?.rawValue == "2026-10-23")
        _ = try await fixture.commands.transitionAction(id: related.id, to: .active, source: .undo, context: fixture.context(42))
        #expect(standalone.goalID == nil)
        #expect(standalone.milestoneID == nil)
        await #expect(throws: CareerWorkContractError.invalidRelationship) {
            try await fixture.commands.createAction(
                goalID: secondGoal.id,
                milestoneID: milestone.id,
                title: "Conflict",
                detail: "",
                dueDay: nil,
                context: fixture.context(60)
            )
        }
        #expect(try await fixture.store.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM actions")
        } == 2)
    }

    @Test func completionReopenAndMistakenCorrectionKeepEvidenceSemanticsAtomic() async throws {
        let fixture = try await CareerWorkFixture()
        defer { fixture.remove() }
        let action = try await fixture.commands.createAction(
            goalID: nil,
            milestoneID: nil,
            title: "Ship review",
            detail: "",
            dueDay: nil,
            context: fixture.context(10)
        )
        let zone = try #require(TimeZone(secondsFromGMT: 0))
        try await WeeklyWorkRepository(store: fixture.store).place(
            actionID: action.id,
            weekContaining: Date(timeIntervalSince1970: 1_798_156_800),
            plannedDay: nil,
            timeZone: zone,
            context: fixture.context(15)
        )

        let completion = try await fixture.commands.completeAction(
            id: action.id,
            evidenceTitle: "Ship review completed",
            context: fixture.context(20)
        )
        let reopened = try await fixture.commands.reopenAction(id: action.id, context: fixture.context(30))
        #expect(completion.action.status == "completed")
        #expect(try await fixture.activePlacementCount(actionID: action.id) == 0)
        #expect(reopened.status == "active")
        #expect(try await fixture.store.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM action_evidence_links WHERE evidence_id = ? AND superseded_by_event_id IS NULL", arguments: [completion.evidence.id])
        } == 1)

        let secondCompletion = try await fixture.commands.completeAction(
            id: action.id,
            evidenceTitle: "Ship review completed again",
            context: fixture.context(40)
        )
        let corrected = try await fixture.commands.undoMistakenCompletion(
            id: action.id,
            completionEventID: secondCompletion.event.id,
            context: fixture.context(50)
        )
        let links = try await fixture.store.read { db in
            try Row.fetchAll(db, sql: "SELECT evidence_id, completion_event_id, superseded_by_event_id FROM action_evidence_links ORDER BY evidence_id").map {
                ($0["evidence_id"] as String, $0["completion_event_id"] as String, $0["superseded_by_event_id"] as String?)
            }
        }
        #expect(corrected.status == "active")
        #expect(links.first(where: { $0.0 == completion.evidence.id })?.2 == nil)
        #expect(links.first(where: { $0.0 == secondCompletion.evidence.id })?.1 == secondCompletion.event.id)
        #expect(links.first(where: { $0.0 == secondCompletion.evidence.id })?.2 != nil)
        #expect(try await fixture.store.read { db in
            try String.fetchOne(db, sql: "SELECT kind FROM action_events WHERE id = ?", arguments: [links.first(where: { $0.0 == secondCompletion.evidence.id })?.2])
        } == "completion_corrected")
    }

    @Test func editChecklistAndPromotionAreValidatedAtomicCommands() async throws {
        let fixture = try await CareerWorkFixture()
        defer { fixture.remove() }
        let goal = try await fixture.commands.createGoal(title: "Goal", detail: "", context: fixture.context(10))
        let action = try await fixture.commands.createAction(goalID: nil, milestoneID: nil, title: "Draft", detail: "", dueDay: nil, context: fixture.context(20))

        let edited = try await fixture.commands.editAction(
            id: action.id,
            title: "Prepare launch",
            detail: "Coordinate review",
            goalID: goal.id,
            milestoneID: nil,
            dueDay: try ActionDueDay(validating: "2026-10-30"),
            expectedUpdatedAtMS: action.updatedAtMS,
            context: fixture.context(30)
        )
        await #expect(throws: CareerWorkContractError.staleTarget) {
            try await fixture.commands.editAction(
                id: action.id, title: "Stale", detail: "", goalID: nil, milestoneID: nil,
                dueDay: nil, expectedUpdatedAtMS: action.updatedAtMS, context: fixture.context(31)
            )
        }

        let first = try await fixture.commands.addChecklistItem(actionID: action.id, title: "Invite team", context: fixture.context(40))
        let second = try await fixture.commands.addChecklistItem(actionID: action.id, title: "Share brief", context: fixture.context(50))
        _ = try await fixture.commands.setChecklistItemCompleted(id: first.id, completed: true, context: fixture.context(60))
        try await fixture.commands.reorderChecklist(actionID: action.id, orderedIDs: [second.id, first.id], context: fixture.context(70))
        let renamed = try await fixture.commands.renameChecklistItem(id: first.id, title: "Invite reviewers", context: fixture.context(75))
        let promoted = try await fixture.commands.promoteChecklistItem(id: second.id, context: fixture.context(80))
        try await fixture.commands.removeChecklistItem(id: first.id, context: fixture.context(90))

        #expect(edited.goalID == goal.id)
        #expect(renamed.title == "Invite reviewers")
        #expect(promoted.checklistItem.state == .promoted)
        #expect(promoted.action.title == second.title)
        #expect(promoted.action.goalID == goal.id)
        #expect(try await fixture.store.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM actions")
        } == 2)
        #expect(try await fixture.store.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM action_checklist_items WHERE action_id = ?", arguments: [action.id])
        } == 1)
    }

    @Test func dropDeleteAndRestoreRemovePlacementWithoutSilentReplacement() async throws {
        let fixture = try await CareerWorkFixture()
        defer { fixture.remove() }
        let weekly = WeeklyWorkRepository(store: fixture.store)
        let action = try await fixture.commands.createAction(goalID: nil, milestoneID: nil, title: "Placed", detail: "", dueDay: nil, context: fixture.context(10))
        let zone = try #require(TimeZone(secondsFromGMT: 0))
        try await weekly.place(actionID: action.id, weekContaining: Date(timeIntervalSince1970: 1_798_156_800), plannedDay: nil, timeZone: zone, context: fixture.context(20))

        let dropped = try await fixture.commands.dropAction(id: action.id, context: fixture.context(30))
        #expect(dropped.status == "dropped")
        #expect(try await fixture.activePlacementCount(actionID: action.id) == 0)
        _ = try await fixture.commands.reopenAction(id: action.id, context: fixture.context(40))
        #expect(try await fixture.activePlacementCount(actionID: action.id) == 0)

        try await weekly.place(actionID: action.id, weekContaining: Date(timeIntervalSince1970: 1_798_156_800), plannedDay: nil, timeZone: zone, context: fixture.context(50))
        try await fixture.commands.deleteAction(id: action.id, context: fixture.context(60))
        #expect(try await fixture.activePlacementCount(actionID: action.id) == 0)
        let restored = try await fixture.commands.restoreAction(id: action.id, context: fixture.context(70))
        #expect(restored.id == action.id)
        #expect(try await fixture.activePlacementCount(actionID: action.id) == 0)
    }

    @Test func completionRetryIsIdempotentAndInjectedInterruptionRollsBack() async throws {
        let fixture = try await CareerWorkFixture()
        defer { fixture.remove() }
        let action = try await fixture.commands.createAction(goalID: nil, milestoneID: nil, title: "Atomic", detail: "", dueDay: nil, context: fixture.context(10))
        let context = fixture.context(20)
        let first = try await fixture.commands.completeAction(id: action.id, evidenceTitle: "Atomic completed", context: context)
        let retry = try await fixture.commands.completeAction(id: action.id, evidenceTitle: "Atomic completed", context: context)
        #expect(first == retry)
        #expect(try await fixture.store.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM action_events WHERE action_id = ? AND kind = 'completed'", arguments: [action.id]) } == 1)
        #expect(try await fixture.store.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM evidence WHERE action_id = ?", arguments: [action.id]) } == 1)

        let interrupted = try await fixture.commands.createAction(goalID: nil, milestoneID: nil, title: "Interrupted", detail: "", dueDay: nil, context: fixture.context(30))
        let failing = CareerWorkCommandRepository(store: fixture.store, failAfterPrimaryMutation: true)
        await #expect(throws: CareerWorkCommandTestError.injectedFailure) {
            try await failing.completeAction(id: interrupted.id, evidenceTitle: "Must not persist", context: fixture.context(40))
        }
        #expect(try await ActionRepository(store: fixture.store).get(id: interrupted.id)?.status == "active")
        #expect(try await fixture.store.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM action_events WHERE action_id = ? AND kind = 'completed'", arguments: [interrupted.id]) } == 0)
        #expect(try await fixture.store.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM evidence WHERE action_id = ?", arguments: [interrupted.id]) } == 0)
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
    func activePlacementCount(actionID: String) async throws -> Int {
        try await store.read { db in
            try Int.fetchOne(db, sql: """
                SELECT count(*) FROM weekly_placements p
                WHERE p.action_id = ?
                  AND NOT EXISTS (SELECT 1 FROM tombstones t WHERE t.entity_type = 'weekly_placement' AND t.entity_id = p.id)
                """, arguments: [actionID]) ?? 0
        }
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private actor CareerWorkKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}
