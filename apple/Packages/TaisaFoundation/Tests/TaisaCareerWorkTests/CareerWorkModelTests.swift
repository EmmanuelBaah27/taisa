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
        try await client.transitionGoal(created.id, .paused)

        #expect(try await client.loadOverview().paused.map(\.id) == [created.id])
        #expect(try await client.loadGoal(created.id)?.goal.status == "paused")
    }
}

private func goal(title: String) -> GoalRecord { .init(id: "11111111-1111-4111-8111-111111111111", title: title, detail: "", status: "active", createdAtMS: 1, updatedAtMS: 1) }
private func snapshot(_ goal: GoalRecord) -> CareerGoalSnapshot { .init(goal: goal, milestones: [], actions: [], evidence: [], provenance: [], progress: .init(summary: "0 of 0 milestones and 0 of 0 actions completed; 0 evidence items recorded.", completedMilestones: 0, milestoneCount: 0, completedActions: 0, actionCount: 0, evidenceCount: 0)) }

private actor CareerMutationRecorder {
    private(set) var values: [String] = []
    func record(_ value: String) { values.append(value) }
}

private actor CareerLoadQueue {
    private var values: [Result<CareerWorkOverview, any Error>]
    init(_ values: [Result<CareerWorkOverview, any Error>]) { self.values = values }
    func next() throws -> CareerWorkOverview { try values.removeFirst().get() }
}

private actor CareerKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}
