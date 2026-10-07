import Foundation
import Testing
import TaisaSecurity
@testable import TaisaStorage
@testable import TaisaSync

private actor CombinedHomeSyncKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}

@Suite(.serialized) struct CombinedHomeSyncTests {
    @Test func weeklyPlacementAndMovementSurviveCrossDeviceSync() async throws {
        let fixture = try await SyncFixture()
        defer { fixture.remove() }
        let deviceID = UUID().uuidString
        let action = ActionRecord(id: UUID().uuidString, goalID: nil, title: "Prepare review", detail: "", status: "open", dueAtMS: nil, createdAtMS: 1, updatedAtMS: 1)
        try await ActionRepository(store: fixture.sender).create(action, context: fixture.context(deviceID: deviceID, at: 1))
        let placement = WeeklyPlacementRecord(id: UUID().uuidString, actionID: action.id, weekStartMS: 100, plannedDayMS: 200, createdAtMS: 2, updatedAtMS: 2)
        try await WeeklyPlacementRepository(store: fixture.sender).create(placement, context: fixture.context(deviceID: deviceID, at: 2))
        let event = WorkEventRecord(id: UUID().uuidString, actionID: action.id, kind: .placed, fromWeekStartMS: nil, toWeekStartMS: 100, sourceType: "user", sourceID: deviceID, occurredAtMS: 2)
        try await WorkEventRepository(store: fixture.sender).create(event, context: fixture.context(deviceID: deviceID, at: 3))

        #expect(await fixture.send().state == .upToDate)
        #expect(await fixture.receive().state == .upToDate)
        #expect(try await WeeklyPlacementRepository(store: fixture.receiver).get(id: placement.id) == placement)
        #expect(try await WorkEventRepository(store: fixture.receiver).get(id: event.id) == event)
    }

    @Test func insightProposalSyncsWithoutBecomingConfirmedTruth() async throws {
        let fixture = try await SyncFixture()
        defer { fixture.remove() }
        let deviceID = UUID().uuidString
        let conversation = ConversationRecord(id: UUID().uuidString, title: "Source", createdAtMS: 1, updatedAtMS: 1)
        try await ConversationRepository(store: fixture.sender).create(conversation, context: fixture.context(deviceID: deviceID, at: 1))
        let proposal = try await InsightCommandRepository(store: fixture.sender).propose(body: "A proposal", sourceType: "conversation", sourceID: conversation.id, context: fixture.context(deviceID: deviceID, at: 2))

        #expect(await fixture.send().state == .upToDate)
        #expect(await fixture.receive().state == .upToDate)
        #expect(try await InsightRevisionRepository(store: fixture.receiver).get(id: proposal.id)?.status == .proposed)
        #expect(try await InsightQuery(store: fixture.receiver).current().isEmpty)
        #expect(try await InsightQuery(store: fixture.receiver).lead(atMS: 10) == nil)
    }

    @Test func confirmedInsightArrivesOnlyWithInspectableSourceAndAcceptedRevision() async throws {
        let fixture = try await SyncFixture()
        defer { fixture.remove() }
        let deviceID = UUID().uuidString
        let conversation = ConversationRecord(id: UUID().uuidString, title: "Grounding", createdAtMS: 1, updatedAtMS: 1)
        try await ConversationRepository(store: fixture.sender).create(conversation, context: fixture.context(deviceID: deviceID, at: 1))
        let commands = InsightCommandRepository(store: fixture.sender)
        let proposal = try await commands.propose(body: "Protect focused mornings.", sourceType: "conversation", sourceID: conversation.id, context: fixture.context(deviceID: deviceID, at: 2))
        let insight = try await commands.confirm(proposalID: proposal.id, editedBody: nil, isTimeSensitive: true, homeEligibleUntilMS: 1_000, context: fixture.context(deviceID: deviceID, at: 3))

        #expect(await fixture.send().state == .upToDate)
        #expect(await fixture.receive().state == .upToDate)
        #expect(try await InsightQuery(store: fixture.receiver).current() == [insight])
        #expect(try await InsightQuery(store: fixture.receiver).sources(insightID: insight.id).map(\.sourceID) == [conversation.id])
        #expect(try await InsightQuery(store: fixture.receiver).revisions(insightID: insight.id).map(\.status) == [.accepted])
    }

    @Test func ungroundedRemoteInsightNeverBecomesCurrentTruth() async throws {
        let fixture = try await SyncFixture()
        defer { fixture.remove() }
        let insight = InsightRecord(id: UUID().uuidString, body: "No evidence", status: .confirmed, isTimeSensitive: true, homeEligibleUntilMS: 1_000, createdAtMS: 1, updatedAtMS: 1)
        try await InsightRepository(store: fixture.sender).create(insight, context: fixture.context(deviceID: UUID().uuidString, at: 1))

        #expect(await fixture.send().state == .upToDate)
        #expect(await fixture.receive().state == .upToDate)
        #expect(try await InsightQuery(store: fixture.receiver).current().isEmpty)
        #expect(try await InsightQuery(store: fixture.receiver).lead(atMS: 10) == nil)
    }

    @Test func malformedRemoteInsightStatusIsRejectedBeforeMaterialization() throws {
        let mutationID = UUID().uuidString
        let entityID = UUID().uuidString
        let deviceID = UUID().uuidString
        let names = ["body", "status", "isTimeSensitive", "homeEligibleUntilMS", "createdAtMS", "updatedAtMS"]
        let causality = CausalSnapshot(logicalVersionID: mutationID, recordParentVersionID: nil, resolvedParentVersionIDs: nil, retainedDeletionCausality: nil, deviceID: deviceID, deviceCounter: 1, changedFields: names.map { FieldCausalVersion(fieldName: $0, versionID: mutationID, parentVersionID: nil, ancestorVersionIDs: [], deviceCounter: 1) }, observedFieldVersions: [])
        let record: [String: Any] = ["id": entityID, "body": "Invalid", "status": "invented", "isTimeSensitive": 1, "homeEligibleUntilMS": NSNull(), "createdAtMS": 1, "updatedAtMS": 1]
        let payload = try JSONSerialization.data(withJSONObject: ["id": mutationID, "deviceID": deviceID, "entityType": "insight", "entityID": entityID, "timestamp": 1, "operation": "create", "record": record, "causality": JSONSerialization.jsonObject(with: JSONEncoder().encode(causality))], options: [.sortedKeys])
        #expect(throws: SyncMergeError.malformedMutation) { _ = try SyncProjection(payload) }
    }

    @Test func remoteInsightWithMissingInspectableSourceIsQuarantined() async throws {
        let fixture = try await SyncFixture()
        defer { fixture.remove() }
        let deviceID = UUID().uuidString
        let insight = InsightRecord(id: UUID().uuidString, body: "Broken grounding", status: .confirmed, isTimeSensitive: true, homeEligibleUntilMS: 1_000, createdAtMS: 1, updatedAtMS: 1)
        try await InsightRepository(store: fixture.sender).create(insight, context: fixture.context(deviceID: deviceID, at: 1))
        try await InsightSourceRepository(store: fixture.sender).create(.init(id: UUID().uuidString, insightID: insight.id, sourceType: "conversation", sourceID: UUID().uuidString, excerpt: "", createdAtMS: 2), context: fixture.context(deviceID: deviceID, at: 2))

        #expect(await fixture.send().state == .recoveryRequired)
        #expect(await fixture.receive().state == .recoveryRequired)
        #expect(try await InsightQuery(store: fixture.receiver).current().isEmpty)
    }
}

private struct SyncFixture {
    let sender: TaisaStore
    let receiver: TaisaStore
    let senderDirectory: URL
    let receiverDirectory: URL
    let vault: Vault
    let transport: InMemorySyncTransport

    init() async throws {
        senderDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        receiverDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: senderDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: receiverDirectory, withIntermediateDirectories: true)
        sender = try await TaisaStore.open(at: senderDirectory.appendingPathComponent("store.sqlite"), keyStore: CombinedHomeSyncKeys())
        receiver = try await TaisaStore.open(at: receiverDirectory.appendingPathComponent("store.sqlite"), keyStore: CombinedHomeSyncKeys())
        vault = try Vault.generate()
        transport = InMemorySyncTransport(accountFingerprint: Data("combined-home".utf8))
    }
    func context(deviceID: String, at timestamp: Int64) -> MutationContext { .init(id: UUID().uuidString, deviceID: deviceID, timestamp: timestamp) }
    func send() async -> SyncOutcome { await SyncCoordinator(store: sender, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual) }
    func receive() async -> SyncOutcome { await SyncCoordinator(store: receiver, vault: vault, transport: transport, nowMS: { 101 }).synchronize(reason: .manual) }
    func remove() {
        try? FileManager.default.removeItem(at: senderDirectory)
        try? FileManager.default.removeItem(at: receiverDirectory)
    }
}
