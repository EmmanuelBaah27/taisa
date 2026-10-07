import Foundation
import GRDB
import Testing
import TaisaStorage
import TaisaSecurity
@testable import TaisaSync

private actor RereviewKeys: DatabaseKeyStore {
    var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ value: Data) async throws { key = value }
}
private actor RereviewTransport: SyncTransport {
    let generation = UUID()
    var pages: [SyncFetchPage] = []
    var errors: [Int: SyncTransportError] = [:]
    var calls = 0
    var fetchedTokens: [Data?] = []
    func accountState() async -> SyncAccountState { .available(fingerprint: Data("A".utf8)) }
    func bind(expectedFingerprint: Data) async throws -> SyncAccountSession { .init(fingerprint: Data("A".utf8), generation: generation) }
    func send(_ changes: [EncryptedChange], session: SyncAccountSession) async throws -> SyncSendResult { .init(acknowledgedIDs: changes.map(\.id)) }
    func configure(_ pages: [SyncFetchPage], errors: [Int: SyncTransportError] = [:]) { self.pages = pages; self.errors = errors; calls = 0; fetchedTokens = [] }
    func fetch(after token: Data?, session: SyncAccountSession) async throws -> SyncFetchPage {
        calls += 1
        fetchedTokens.append(token)
        if let error = errors[calls] { throw error }
        if !pages.isEmpty { return pages.removeFirst() }
        return .init(changes: [], token: token)
    }
}

@Suite(.serialized) struct Task6RereviewTests {
    func store() async throws -> TaisaStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("task6-rereview-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return try await TaisaStore.open(at: url.appendingPathComponent("store.sqlite"), keyStore: RereviewKeys())
    }
    func context(_ device: String = UUID().uuidString, time: Int64 = 10) -> MutationContext { .init(id: UUID().uuidString, deviceID: device, timestamp: time) }
    func changes(_ store: TaisaStore, _ vault: Vault) async throws -> [EncryptedChange] {
        try await ChangeJournal(store: store).pending(limit: 200).map {
            .init(id: $0.id, envelope: try vault.seal($0.payload, metadata: .init(vaultID: vault.id, recordID: UUID(uuidString: $0.id)!, entityType: $0.entityType, schemaVersion: 1, tombstone: false)))
        }
    }
    @Test func legacyCheckpointDecodesDefaults() throws {
        let checkpoint = try JSONDecoder().decode(SyncEngineCheckpoint.self, from: Data("{\"received\":{},\"retryAtMS\":2000}".utf8))
        #expect(checkpoint.retryAtMS == 2000)
        #expect(checkpoint.retryAttempts == 0)
        #expect(checkpoint.turnGeneration == 0)
        #expect(checkpoint.recoveryState == nil)
        #expect(!checkpoint.recoveryPrepared)
    }
    @Test func zoneRecoveryResumesAfterCommittedPageAndNetworkFailure() async throws {
        let db = try await store(), vault = try Vault.generate(), transport = RereviewTransport()
        await transport.configure([], errors: [1: .zoneReset])
        let coordinator = SyncCoordinator(store: db, vault: vault, transport: transport, nowMS: { 100 })
        #expect(await coordinator.synchronize(reason: .manual).state == .zoneReset)
        await transport.configure([.init(changes: [], token: Data("1".utf8), hasMore: true)], errors: [2: .retryable])
        #expect(await coordinator.reconcileZoneAfterReset().state == .zoneReset)
        let token = try await db.read { try Data.fetchOne($0, sql: "SELECT change_token FROM sync_state WHERE id=1") }
        #expect(token == Data("1".utf8))
        await transport.configure([.init(changes: [], token: Data("2".utf8))])
        let relaunched = SyncCoordinator(store: db, vault: vault, transport: transport, nowMS: { 2000 })
        #expect(await relaunched.reconcileZoneAfterReset().state == .upToDate)
        #expect(await transport.fetchedTokens.first == Data("1".utf8))
        #expect(await relaunched.synchronize(reason: .foreground).state == .upToDate)
    }

    @Test func zoneRecoveryContinuesAfterPageBudgetFromDurableCursor() async throws {
        let db = try await store(), vault = try Vault.generate(), transport = RereviewTransport()
        await transport.configure([], errors: [1: .zoneReset])
        #expect(await SyncCoordinator(store: db, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual).state == .zoneReset)
        let pages = (1...1000).map { index in
            SyncFetchPage(changes: [], token: Data(String(index).utf8), hasMore: true)
        }
        await transport.configure(pages)
        #expect(await SyncCoordinator(store: db, vault: vault, transport: transport, nowMS: { 200 }).reconcileZoneAfterReset().state == .zoneReset)
        let committed = try await db.read { try Data.fetchOne($0, sql: "SELECT change_token FROM sync_state WHERE id = 1") }
        #expect(committed == Data("1000".utf8))
        await transport.configure([.init(changes: [], token: Data("done".utf8))])
        #expect(await SyncCoordinator(store: db, vault: vault, transport: transport, nowMS: { 2000 }).reconcileZoneAfterReset().state == .upToDate)
        #expect(await transport.fetchedTokens.first == Data("1000".utf8))
    }
    @Test func existingActionRelationshipUpdateDefersForLaterParentPage() async throws {
        let sender = try await store(), receiver = try await store(), vault = try Vault.generate(), transport = RereviewTransport()
        let id = UUID().uuidString, goal = UUID().uuidString, device = UUID().uuidString
        let repo = ActionRepository(store: sender)
        try await repo.create(.init(id: id, goalID: nil, title: "Action", detail: "", status: "open", dueAtMS: nil, createdAtMS: 10, updatedAtMS: 10), context: context(device))
        let first = try await changes(sender, vault)
        await transport.configure([.init(changes: first, token: Data("1".utf8))])
        let coordinator = SyncCoordinator(store: receiver, vault: vault, transport: transport, nowMS: { 100 })
        #expect(await coordinator.synchronize(reason: .manual).state == .upToDate)
        try await GoalRepository(store: sender).create(.init(id: goal, title: "Goal", detail: "", status: "active", createdAtMS: 11, updatedAtMS: 11), context: context(device, time: 11))
        try await repo.update(.init(id: id, goalID: goal, title: "Action", detail: "", status: "open", dueAtMS: nil, createdAtMS: 10, updatedAtMS: 12), context: context(device, time: 12))
        let all = try await changes(sender, vault)
        await transport.configure([.init(changes: [all[2]], token: Data("2".utf8), hasMore: true), .init(changes: [all[1]], token: Data("3".utf8))])
        #expect(await coordinator.synchronize(reason: .manual).state == .upToDate)
        #expect(try await ActionRepository(store: receiver).get(id: id)?.goalID == goal)
        #expect(await transport.calls == 2)
    }
    @Test func mixedPartialFailurePreservesServerRetryDeadline() async throws {
        let db = try await store(), vault = try Vault.generate(), transport = InMemorySyncTransport(accountFingerprint: Data("A".utf8))
        let first = context(), second = context(), third = context()
        let repo = ProfileRepository(store: db)
        try await repo.create(.init(id: UUID().uuidString, displayName: "One", headline: "", biography: "", updatedAtMS: 10), context: first)
        try await repo.create(.init(id: UUID().uuidString, displayName: "Two", headline: "", biography: "", updatedAtMS: 10), context: second)
        try await repo.create(.init(id: UUID().uuidString, displayName: "Three", headline: "", biography: "", updatedAtMS: 10), context: third)
        await transport.failNextItems([first.id: .quota, second.id: .rateLimited(retryAfterMS: 9000), third.id: .offline])
        let failed = await SyncCoordinator(store: db, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual)
        #expect(failed.state == .storageFull)
        #expect(failed.retryAtMS == 9000)
        let result = await SyncCoordinator(store: db, vault: vault, transport: transport, nowMS: { 200 }).synchronize(reason: .manual)
        #expect(result.uploaded == 0)
        #expect(await transport.allChanges().isEmpty)
    }
    @Test func fetchBackoffSurvivesRelaunchAndResetsAfterProgress() async throws {
        let db = try await store(), vault = try Vault.generate(), transport = RereviewTransport()
        await transport.configure([], errors: [1: .retryable])
        #expect(await SyncCoordinator(store: db, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual).retryAtMS == 1100)
        await transport.configure([], errors: [1: .retryable])
        #expect(await SyncCoordinator(store: db, vault: vault, transport: transport, nowMS: { 2000 }).synchronize(reason: .manual).retryAtMS == 4000)
        await transport.configure([.init(changes: [], token: Data("done".utf8))])
        #expect(await SyncCoordinator(store: db, vault: vault, transport: transport, nowMS: { 5000 }).synchronize(reason: .manual).state == .upToDate)
        await transport.configure([], errors: [1: .retryable])
        #expect(await SyncCoordinator(store: db, vault: vault, transport: transport, nowMS: { 6000 }).synchronize(reason: .manual).retryAtMS == 7000)
    }
    @Test(arguments: [false, true]) func receivedResolutionIsParentOfNextLocalEdit(changeTimestamp: Bool) async throws {
        let aStore = try await store(), bStore = try await store(), vault = try Vault.generate()
        let transport = InMemorySyncTransport(accountFingerprint: Data("A".utf8))
        let a = SyncCoordinator(store: aStore, vault: vault, transport: transport, nowMS: { 100 })
        let b = SyncCoordinator(store: bStore, vault: vault, transport: transport, nowMS: { 100 })
        let id = UUID().uuidString, ad = UUID().uuidString, bd = UUID().uuidString
        func profile(_ name: String, _ time: Int64) -> ProfileRecord { .init(id: id, displayName: name, headline: "", biography: "", updatedAtMS: changeTimestamp ? time : 10) }
        try await ProfileRepository(store: aStore).create(profile("Base", 10), context: context(ad))
        _ = await a.synchronize(reason: .manual); _ = await b.synchronize(reason: .manual)
        try await ProfileRepository(store: aStore).update(profile("First", 11), context: context(ad, time: 11))
        try await ProfileRepository(store: bStore).update(profile("Second", 11), context: context(bd, time: 11))
        _ = await a.synchronize(reason: .manual); _ = await b.synchronize(reason: .manual); _ = await a.synchronize(reason: .manual)
        let conflict = try #require(await ConflictStore(store: aStore).unresolved().first { $0.fieldName == "displayName" })
        let resolution = try conflict.resolve(value: Data("\"Chosen\"".utf8), mutationID: UUID().uuidString, deviceID: UUID().uuidString, counter: 1, timestampMS: 12)
        try await a.resolveConflict(conflict, using: resolution)
        _ = await a.synchronize(reason: .manual); _ = await b.synchronize(reason: .manual)
        try await ProfileRepository(store: bStore).update(profile("After", 13), context: context(bd, time: 13))
        let mutation = try #require(await ChangeJournal(store: bStore).pending(limit: 10).first)
        #expect(mutation.causality.changedFields.first { $0.fieldName == "displayName" }?.parentVersionID == resolution.id)
        #expect(await b.synchronize(reason: .manual).state == .upToDate)
        #expect(await a.synchronize(reason: .manual).state == .upToDate)
        #expect(try await ProfileRepository(store: aStore).get(id: id)?.displayName == "After")
        let remaining = try await ConflictStore(store: aStore).unresolved().map(\.fieldName)
        #expect(remaining.isEmpty)
    }
    @Test func equalValueConvergenceRetainsBothObservedFieldHeads() async throws {
        let aStore = try await store(), bStore = try await store(), vault = try Vault.generate()
        let transport = InMemorySyncTransport(accountFingerprint: Data("A".utf8))
        let a = SyncCoordinator(store: aStore, vault: vault, transport: transport, nowMS: { 100 })
        let b = SyncCoordinator(store: bStore, vault: vault, transport: transport, nowMS: { 100 })
        let id = UUID().uuidString, ad = UUID().uuidString, bd = UUID().uuidString
        func profile(_ name: String) -> ProfileRecord { .init(id: id, displayName: name, headline: "", biography: "", updatedAtMS: 10) }
        try await ProfileRepository(store: aStore).create(profile("Base"), context: context(ad))
        _ = await a.synchronize(reason: .manual); _ = await b.synchronize(reason: .manual)
        let aEdit = MutationContext(id: "11111111-1111-4111-8111-111111111111", deviceID: ad, timestamp: 11)
        let bEdit = MutationContext(id: "22222222-2222-4222-8222-222222222222", deviceID: bd, timestamp: 11)
        try await ProfileRepository(store: aStore).update(profile("Same"), context: aEdit)
        try await ProfileRepository(store: bStore).update(profile("Same"), context: bEdit)
        #expect(await a.synchronize(reason: .manual).state == .upToDate)
        #expect(await b.synchronize(reason: .manual).state == .upToDate)
        #expect(await a.synchronize(reason: .manual).state == .upToDate)
        try await ProfileRepository(store: bStore).update(profile("Later"), context: context(bd, time: 12))
        let later = try #require(await ChangeJournal(store: bStore).pending(limit: 10).last)
        let name = try #require(later.causality.changedFields.first { $0.fieldName == "displayName" })
        #expect(Set(name.ancestorVersionIDs).isSuperset(of: [aEdit.id, bEdit.id]))
        #expect(name.ancestorVersionIDs.first == name.parentVersionID)
        #expect(await b.synchronize(reason: .manual).state == .upToDate)
        #expect(await a.synchronize(reason: .manual).state == .upToDate)
        let remaining = try await ConflictStore(store: aStore).unresolved().map(\.fieldName)
        #expect(remaining.isEmpty)
    }

    @Test func evidenceRelationshipUpdateWaitsForBothLaterParents() async throws {
        let sender = try await store(), receiver = try await store(), vault = try Vault.generate(), transport = RereviewTransport()
        let evidenceID = UUID().uuidString, goalID = UUID().uuidString, actionID = UUID().uuidString, device = UUID().uuidString
        let evidence = EvidenceRepository(store: sender)
        try await evidence.create(.init(id: evidenceID, goalID: nil, actionID: nil, title: "Proof", detail: "", occurredAtMS: 10, createdAtMS: 10), context: context(device))
        let initial = try await changes(sender, vault)
        await transport.configure([.init(changes: initial, token: Data("1".utf8))])
        let coordinator = SyncCoordinator(store: receiver, vault: vault, transport: transport, nowMS: { 100 })
        #expect(await coordinator.synchronize(reason: .manual).state == .upToDate)
        try await GoalRepository(store: sender).create(.init(id: goalID, title: "Goal", detail: "", status: "active", createdAtMS: 11, updatedAtMS: 11), context: context(device, time: 11))
        try await ActionRepository(store: sender).create(.init(id: actionID, goalID: goalID, title: "Action", detail: "", status: "open", dueAtMS: nil, createdAtMS: 12, updatedAtMS: 12), context: context(device, time: 12))
        try await evidence.update(.init(id: evidenceID, goalID: goalID, actionID: actionID, title: "Proof", detail: "", occurredAtMS: 13, createdAtMS: 10), context: context(device, time: 13))
        let all = try await changes(sender, vault)
        await transport.configure([
            .init(changes: [all[3]], token: Data("2".utf8), hasMore: true),
            .init(changes: [all[2]], token: Data("3".utf8), hasMore: true),
            .init(changes: [all[1]], token: Data("4".utf8)),
        ])
        #expect(await coordinator.synchronize(reason: .manual).state == .upToDate)
        #expect(try await evidenceIn(receiver, evidenceID)?.goalID == goalID)
        #expect(try await evidenceIn(receiver, evidenceID)?.actionID == actionID)
        #expect(await transport.calls == 3)
    }

    private func evidenceIn(_ db: TaisaStore, _ id: String) async throws -> EvidenceRecord? {
        try await EvidenceRepository(store: db).get(id: id)
    }

    @Test func memorySourceParentMoveWaitsForLaterMemoryPage() async throws {
        let sender = try await store(), receiver = try await store(), vault = try Vault.generate(), transport = RereviewTransport()
        let oldID = UUID().uuidString, newID = UUID().uuidString, sourceID = UUID().uuidString, device = UUID().uuidString
        let memory = MemoryRepository(store: sender)
        try await memory.create(.init(id: oldID, kind: "fact", content: "Old", status: "active", createdAtMS: 10, updatedAtMS: 10), context: context(device))
        try await memory.createSource(.init(id: sourceID, memoryItemID: oldID, sourceType: "note", sourceID: UUID().uuidString, createdAtMS: 11), context: context(device, time: 11))
        let initial = try await changes(sender, vault)
        await transport.configure([.init(changes: initial, token: Data("1".utf8))])
        let coordinator = SyncCoordinator(store: receiver, vault: vault, transport: transport, nowMS: { 100 })
        #expect(await coordinator.synchronize(reason: .manual).state == .upToDate)
        try await memory.create(.init(id: newID, kind: "fact", content: "New", status: "active", createdAtMS: 12, updatedAtMS: 12), context: context(device, time: 12))
        let oldSource = try #require(await memory.source(id: sourceID))
        try await memory.updateSource(.init(id: sourceID, memoryItemID: newID, sourceType: oldSource.sourceType, sourceID: oldSource.sourceID, createdAtMS: 11), context: context(device, time: 13))
        let all = try await changes(sender, vault)
        await transport.configure([
            .init(changes: [all[3]], token: Data("2".utf8), hasMore: true),
            .init(changes: [all[2]], token: Data("3".utf8)),
        ])
        #expect(await coordinator.synchronize(reason: .manual).state == .upToDate)
        #expect(try await MemoryRepository(store: receiver).source(id: sourceID)?.memoryItemID == newID)
    }

    @Test func identicalMemorySourceCreatesRetainBothVisibleHeads() throws {
        let entity = UUID().uuidString, parent = UUID().uuidString
        let firstID = "11111111-1111-4111-8111-111111111111"
        let secondID = "22222222-2222-4222-8222-222222222222"
        func creation(_ id: String) -> SyncMutation {
            .init(id: id, entityType: "memory_source", entityID: entity, entityVersion: 1,
                  deviceID: UUID().uuidString, counter: 1, timestampMS: 10, kind: .create,
                  fields: [.init(name: "memoryItemID", value: Data(parent.utf8), versionID: id, deviceCounter: 1)])
        }
        let decision = try MergeEngine.reduce(events: [creation(firstID), creation(secondID)])
        #expect(decision.kind == .duplicate)
        #expect(decision.visibleFieldHeads["memoryItemID"] == [firstID.uppercased(), secondID.uppercased()])
    }
}
