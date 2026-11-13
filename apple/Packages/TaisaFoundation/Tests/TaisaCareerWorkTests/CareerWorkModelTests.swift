import Foundation
import Testing
@testable import TaisaCareerWork
import TaisaStorage

@Suite(.serialized) @MainActor struct CareerWorkModelTests {
    @Test func loadAndStableSelectionPublishOwnedSnapshot() async {
        let goal = goal(title: "Launch")
        let overview = CareerWorkOverview(active: [goal], paused: [], completed: [], archived: [])
        let detail = snapshot(goal)
        let client = CareerWorkClient(loadOverview: { overview }, loadGoal: { $0 == goal.id ? detail : nil })
        let model = CareerWorkModel(client: client)

        await model.load()
        #expect(model.state == .content(.init(overview: overview, selectedGoal: nil), isRefreshing: false, issue: nil))
        await model.select(.goal(id: goal.id))
        #expect(model.route.stableID == "goal:\(goal.id)")
        #expect(model.state.snapshot?.selectedGoal == detail)
    }

    @Test func createAndLifecycleIntentReloadLocalTruth() async {
        let recorder = CareerMutationRecorder()
        let created = goal(title: "Created")
        let client = CareerWorkClient(
            loadOverview: { CareerWorkOverview(active: [created], paused: [], completed: [], archived: []) },
            loadGoal: { _ in snapshot(created) },
            createGoal: { title, detail in await recorder.record("create:\(title):\(detail)"); return created },
            transitionGoal: { id, status in await recorder.record("transition:\(id):\(status.rawValue)") }
        )
        let model = CareerWorkModel(client: client)

        await model.createGoal(title: "Created", detail: "Detail")
        await model.transitionSelectedGoal(to: .paused)

        #expect(await recorder.values == ["create:Created:Detail", "transition:\(created.id):paused"])
        #expect(model.route == .goal(id: created.id))
        #expect(model.state.snapshot?.selectedGoal?.goal.id == created.id)
    }

    @Test func conflictsInvalidInputAndRecoveryStayDistinct() async {
        let goal = goal(title: "Goal")
        let conflict = CareerWorkModel(client: .init(loadOverview: { throw CareerWorkProposalError.staleTarget }))
        await conflict.load()
        #expect(conflict.state == .failure(.conflict))

        let invalid = CareerWorkModel(client: .init(loadOverview: { CareerWorkOverview(active: [goal], paused: [], completed: [], archived: []) }, createGoal: { _, _ in throw CareerWorkContractError.invalidTitle }))
        await invalid.createGoal(title: "", detail: "")
        #expect(invalid.state.issue == .invalidInput)

        let recovery = CareerWorkModel(client: .init(loadOverview: { throw StorageError.integrityFailed }))
        await recovery.load()
        #expect(recovery.state == .failure(.recoveryRequired))
    }

    @Test func retryRecoversWithoutLosingSelectedRoute() async {
        let goal = goal(title: "Recovered")
        let queue = CareerLoadQueue([.failure(StorageError.openFailed), .success(CareerWorkOverview(active: [goal], paused: [], completed: [], archived: []))])
        let model = CareerWorkModel(client: .init(loadOverview: { try await queue.next() }))

        await model.select(.goal(id: goal.id))
        #expect(model.state == .failure(.storageUnavailable))
        await model.retry()
        #expect(model.route == .goal(id: goal.id))
        #expect(model.state.snapshot?.overview.active.map(\.id) == [goal.id])
    }

    @Test func localClientWorksOfflineAgainstEncryptedStoreOnly() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("career.sqlite"), keyStore: CareerKeys())
        let client = CareerWorkClient.local(store: store, deviceID: UUID().uuidString, nowMS: { 100 })

        let created = try await client.createGoal("Offline goal", "No provider")
        let milestone = try await client.createMilestone(created.id, "First proof point", 200)
        let action = try await client.createAction(created.id, "Collect feedback", "Ask three peers", 300)
        let evidence = try await client.addEvidence(created.id, action.id, "Feedback received", "Three responses", 150)
        try await client.transitionGoal(created.id, .paused)

        #expect(try await client.loadOverview().paused.map(\.id) == [created.id])
        let reloaded = try await client.loadGoal(created.id)
        #expect(reloaded?.goal.status == "paused")
        #expect(reloaded?.milestones.map(\.id) == [milestone.id])
        #expect(reloaded?.actions.map(\.id) == [action.id])
        #expect(reloaded?.evidence.map(\.id) == [evidence.id])
        #expect(reloaded?.provenance.first?.origin == .user)
        #expect(try await client.loadAction(action.id)?.id == action.id)
        #expect(try await client.loadEvidence(evidence.id)?.id == evidence.id)
    }

    @Test func standaloneActionCreationStopsAtDuplicateGateUntilExplicitDecision() async {
        let existing = ActionRecord(id: UUID().uuidString, goalID: nil, title: "Prepare launch", detail: "", status: "active", dueAtMS: nil, createdAtMS: 1, updatedAtMS: 1)
        let recorder = CareerMutationRecorder()
        let client = CareerWorkClient(
            loadOverview: { .init(active: [], paused: [], completed: [], archived: []) },
            loadActions: { _, _ in [existing] },
            reviewActionDuplicates: { _, _ in .init(candidates: [existing]) },
            createCanonicalAction: { draft in await recorder.record("create:\(draft.title)"); return existing }
        )
        let model = CareerWorkModel(client: client)
        let draft = ActionDraft(title: " Prepare launch ", detail: "", parent: .standalone, dueDay: nil)

        await model.createAction(draft)
        #expect(model.duplicateGate?.candidates.map(\.id) == [existing.id])
        #expect(await recorder.values.isEmpty)

        await model.resolveDuplicate(.createSeparate)
        #expect(await recorder.values == ["create:Prepare launch"])
        #expect(model.duplicateGate == nil)
        #expect(model.route == .action(id: existing.id))
    }

    @Test func localCanonicalClientCreatesStandaloneAndRunsChecklistLifecycle() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("actions.sqlite"), keyStore: CareerKeys())
        let client = CareerWorkClient.local(store: store, deviceID: UUID().uuidString, nowMS: { 100 })
        let draft = ActionDraft(title: "Standalone", detail: "Detail", parent: .standalone, dueDay: try ActionDueDay(validating: "2026-10-23"))

        let action = try await client.createCanonicalAction(draft)
        let item = try await client.addChecklistItem(action.id, "First step")
        _ = try await client.setChecklistItemCompleted(item.id, true)
        let completion = try await client.completeAction(action.id, "Standalone completed")
        _ = try await client.reopenAction(action.id)

        #expect(try await client.loadActions(.init(lifecycle: .active), try ActionDueDay(validating: "2026-10-23")).map(\.id) == [action.id])
        let detail = try #require(try await client.loadActionDetail(action.id))
        #expect(detail.checklist.first?.state == .completed)
        #expect(detail.currentEvidence.map(\.id) == [completion.evidence.id])
    }

    @Test func staleEditPublishesConflictWithoutDiscardingRetainedActionDetail() async {
        let action = ActionRecord(id: UUID().uuidString, goalID: nil, title: "Current", detail: "", status: "active", dueAtMS: nil, createdAtMS: 1, updatedAtMS: 2)
        let detail = ActionDetailSnapshot(action: action, goal: nil, milestone: nil, checklist: [], events: [], currentEvidence: [], supersededEvidence: [], placement: nil)
        let overview = CareerWorkOverview(active: [], paused: [], completed: [], archived: [])
        let client = CareerWorkClient(
            loadOverview: { overview },
            loadActions: { _, _ in [action] },
            loadActionDetail: { _ in detail },
            editCanonicalAction: { _, _, _ in throw CareerWorkContractError.staleTarget }
        )
        let model = CareerWorkModel(client: client, route: .action(id: action.id))
        await model.load()
        await model.editSelectedAction(.init(title: "Changed", detail: "", parent: .standalone, dueDay: nil), expectedUpdatedAtMS: 1)

        #expect(model.state.issue == .conflict)
        #expect(model.state.snapshot?.selectedActionDetail == detail)
    }

    @Test func olderCancelledLoadCannotOverwriteNewerGeneration() async {
        let old = goal(title: "Old")
        let new = GoalRecord(id: UUID().uuidString, title: "New", detail: "", status: "active", createdAtMS: 2, updatedAtMS: 2)
        let race = CareerOverviewRace(old: .init(active: [old], paused: [], completed: [], archived: []), new: .init(active: [new], paused: [], completed: [], archived: []))
        let model = CareerWorkModel(client: .init(loadOverview: { await race.next() }))

        let first = Task { await model.load() }
        await race.waitUntilFirstSuspends()
        await model.load()
        await race.releaseFirst()
        await first.value

        #expect(model.state.snapshot?.overview.active.map(\.id) == [new.id])
    }

    @Test func failedRefreshRetainsLastGoodSnapshotAndPublishesIssue() async {
        let current = goal(title: "Retained")
        let queue = CareerLoadQueue([.success(.init(active: [current], paused: [], completed: [], archived: [])), .failure(StorageError.openFailed)])
        let model = CareerWorkModel(client: .init(loadOverview: { try await queue.next() }))
        await model.load()
        await model.load()
        #expect(model.state.snapshot?.overview.active.map(\.id) == [current.id])
        #expect(model.state.issue == .storageUnavailable)
    }

    @Test func changingActionFilterReloadsExactLocalDayAndPreservesSelection() async throws {
        let action = ActionRecord(id: UUID().uuidString, goalID: nil, title: "Selected", detail: "", status: "active", dueAtMS: nil, createdAtMS: 1, updatedAtMS: 1)
        let detail = ActionDetailSnapshot(action: action, goal: nil, milestone: nil, checklist: [], events: [], currentEvidence: [], supersededEvidence: [], placement: nil)
        let expectedDay = try ActionDueDay(validating: "2026-10-23")
        let expectedFilter = ActionCollectionFilter(lifecycle: .completed)
        let recorder = ActionLoadRecorder()
        let client = CareerWorkClient(
            loadOverview: { .init(active: [], paused: [], completed: [], archived: []) },
            loadActions: { filter, day in await recorder.record(filter: filter, day: day); return [action] },
            loadActionDetail: { _ in detail }
        )
        let model = CareerWorkModel(client: client, route: .action(id: action.id), localDay: { expectedDay })

        await model.setActionFilter(expectedFilter)

        #expect(await recorder.lastFilter == expectedFilter)
        #expect(await recorder.lastDay == expectedDay)
        #expect(model.route == .action(id: action.id))
        #expect(model.state.snapshot?.selectedActionDetail == detail)
    }

    @Test func loadPublishesDurableParentOptionsAndDeletedActions() async {
        let parent = goal(title: "Parent")
        let milestone = MilestoneRecord(id: UUID().uuidString, goalID: parent.id, title: "Proof", status: "planned", targetAtMS: nil, updatedAtMS: 2)
        let deleted = ActionRecord(id: UUID().uuidString, goalID: nil, title: "Recover me", detail: "", status: "active", dueAtMS: nil, createdAtMS: 1, updatedAtMS: 3)
        let model = CareerWorkModel(client: .init(
            loadOverview: { .init(active: [parent], paused: [], completed: [], archived: []) },
            loadMilestones: { [milestone] },
            loadDeletedActions: { [deleted] }
        ))

        await model.load()

        #expect(model.state.snapshot?.milestones == [milestone])
        #expect(model.state.snapshot?.deletedActions == [deleted])
    }

    @Test func mistakenCompletionCorrectionUsesSelectedCompletionEventAndReloads() async {
        let action = ActionRecord(id: UUID().uuidString, goalID: nil, title: "Correct me", detail: "", status: "completed", dueAtMS: nil, createdAtMS: 1, updatedAtMS: 2)
        let completionID = UUID().uuidString
        let recorder = CareerMutationRecorder()
        let client = CareerWorkClient(
            loadOverview: { .init(active: [], paused: [], completed: [], archived: []) },
            loadActionDetail: { _ in .init(action: action, goal: nil, milestone: nil, checklist: [], events: [], currentEvidence: [], supersededEvidence: [], placement: nil) },
            undoMistakenCompletion: { id, eventID in await recorder.record("correct:\(id):\(eventID)"); return action }
        )
        let model = CareerWorkModel(client: client, route: .action(id: action.id))

        await model.correctSelectedCompletion(eventID: completionID)

        #expect(await recorder.values == ["correct:\(action.id):\(completionID)"])
        #expect(model.route == .action(id: action.id))
    }

    @Test func restoreRemainsAvailableAfterModelReconstruction() async {
        let deleted = ActionRecord(id: UUID().uuidString, goalID: nil, title: "Recover me", detail: "", status: "active", dueAtMS: nil, createdAtMS: 1, updatedAtMS: 2)
        let recorder = CareerMutationRecorder()
        let client = CareerWorkClient(
            loadOverview: { .init(active: [], paused: [], completed: [], archived: []) },
            loadDeletedActions: { [deleted] },
            restoreAction: { id in await recorder.record("restore:\(id)"); return deleted }
        )
        let reconstructed = CareerWorkModel(client: client)
        await reconstructed.load()
        #expect(reconstructed.state.snapshot?.deletedActions == [deleted])

        await reconstructed.restoreAction(id: deleted.id)

        #expect(await recorder.values == ["restore:\(deleted.id)"])
        #expect(reconstructed.route == .action(id: deleted.id))
    }
}

private func goal(title: String) -> GoalRecord { .init(id: "11111111-1111-4111-8111-111111111111", title: title, detail: "", status: "active", createdAtMS: 1, updatedAtMS: 1) }
private func snapshot(_ goal: GoalRecord) -> CareerGoalSnapshot { .init(goal: goal, milestones: [], actions: [], evidence: [], provenance: [], progress: .init(summary: "0 of 0 milestones and 0 of 0 actions completed; 0 evidence items recorded.", completedMilestones: 0, milestoneCount: 0, completedActions: 0, actionCount: 0, evidenceCount: 0)) }

private actor CareerMutationRecorder {
    private(set) var values: [String] = []
    func record(_ value: String) { values.append(value) }
}

private actor ActionLoadRecorder {
    private(set) var lastFilter: ActionCollectionFilter?
    private(set) var lastDay: ActionDueDay?
    func record(filter: ActionCollectionFilter, day: ActionDueDay) {
        lastFilter = filter
        lastDay = day
    }
}

private actor CareerLoadQueue {
    private var values: [Result<CareerWorkOverview, any Error>]
    init(_ values: [Result<CareerWorkOverview, any Error>]) { self.values = values }
    func next() throws -> CareerWorkOverview { try values.removeFirst().get() }
}

private actor CareerOverviewRace {
    private let old: CareerWorkOverview
    private let new: CareerWorkOverview
    private var calls = 0
    private var firstContinuation: CheckedContinuation<CareerWorkOverview, Never>?

    init(old: CareerWorkOverview, new: CareerWorkOverview) { self.old = old; self.new = new }
    func next() async -> CareerWorkOverview {
        calls += 1
        if calls == 1 { return await withCheckedContinuation { firstContinuation = $0 } }
        return new
    }
    func waitUntilFirstSuspends() async {
        while firstContinuation == nil { await Task.yield() }
    }
    func releaseFirst() {
        firstContinuation?.resume(returning: old)
        firstContinuation = nil
    }
}

private actor CareerKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}
