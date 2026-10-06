import Foundation
import GRDB
import Testing
import TaisaSecurity
import TaisaStorage
import TaisaSync

private actor ReviewKeys: DatabaseKeyStore {
    var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ value: Data) async throws { key = value }
}

private actor ReviewTransport: SyncTransport {
    var account = Data("A".utf8)
    var generation = UUID()
    var pages: [SyncFetchPage] = []
    var failSend = false
    var switchOnSend = false
    var sentAccounts: [Data] = []
    var fetchCounter = 0
    var emptyPages = 0
    func accountState() async -> SyncAccountState { .available(fingerprint: account) }
    func bind(expectedFingerprint: Data) async throws -> SyncAccountSession {
        guard expectedFingerprint == account else { throw SyncTransportError.accountChanged }
        return SyncAccountSession(fingerprint: account, generation: generation)
    }
    func configure(pages: [SyncFetchPage] = [], failSend: Bool = false, switchOnSend: Bool = false, emptyPages: Int = 0) {
        self.pages = pages; self.failSend = failSend; self.switchOnSend = switchOnSend; self.emptyPages = emptyPages
    }
    func send(_ changes: [EncryptedChange], session: SyncAccountSession) async throws -> SyncSendResult {
        if failSend { throw SyncTransportError.retryable }
        if switchOnSend { account = Data("B".utf8); generation = UUID() }
        guard session.fingerprint == account, session.generation == generation else { throw SyncTransportError.accountChanged }
        if !changes.isEmpty { sentAccounts.append(account) }
        return SyncSendResult(acknowledgedIDs: changes.map(\.id))
    }
    func fetch(after token: Data?, session: SyncAccountSession) async throws -> SyncFetchPage {
        guard session.fingerprint == account, session.generation == generation else { throw SyncTransportError.accountChanged }
        fetchCounter += 1
        if emptyPages > 0 {
            let cursor = token.flatMap { String(data: $0, encoding: .utf8) }.flatMap(Int.init) ?? 0
            let next = cursor + 1
            return SyncFetchPage(changes: [], token: Data(String(next).utf8), hasMore: next < emptyPages)
        }
        if !pages.isEmpty { return pages.removeFirst() }
        return SyncFetchPage(changes: [], token: token)
    }
}

private actor OverlapTransport: SyncTransport {
    var count = 0
    let generation = UUID()
    var firstResponse: CheckedContinuation<SyncFetchPage, Never>?
    var firstEntered: CheckedContinuation<Void, Never>?
    func accountState() async -> SyncAccountState { .available(fingerprint: Data("A".utf8)) }
    func bind(expectedFingerprint: Data) async throws -> SyncAccountSession { SyncAccountSession(fingerprint: Data("A".utf8), generation: generation) }
    func send(_ changes: [EncryptedChange], session: SyncAccountSession) async throws -> SyncSendResult { SyncSendResult(acknowledgedIDs: changes.map(\.id)) }
    func waitForFirst() async {
        if count > 0 { return }
        await withCheckedContinuation { firstEntered = $0 }
    }
    func releaseFirst() { firstResponse?.resume(returning: SyncFetchPage(changes: [], token: Data("older".utf8))); firstResponse = nil }
    func fetch(after token: Data?, session: SyncAccountSession) async throws -> SyncFetchPage {
        count += 1
        if count == 1 {
            return await withCheckedContinuation { continuation in
                firstResponse = continuation
                firstEntered?.resume(); firstEntered = nil
            }
        }
        return SyncFetchPage(changes: [], token: Data("newer".utf8))
    }
}

@Suite(.serialized) struct Task6IndependentReviewTests {
    func device() async throws -> TaisaStore {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("task6-independent-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try await TaisaStore.open(at: root.appendingPathComponent("store.sqlite"), keyStore: ReviewKeys())
    }
    func context(_ device: String = UUID().uuidString, time: Int64 = 10) -> MutationContext {
        MutationContext(id: UUID().uuidString, deviceID: device, timestamp: time)
    }
    func profile(_ id: String, _ value: String, time: Int64 = 10) -> ProfileRecord {
        ProfileRecord(id: id, displayName: value, headline: "", biography: "", updatedAtMS: time)
    }
    func changes(_ store: TaisaStore, _ vault: Vault) async throws -> [EncryptedChange] {
        try await ChangeJournal(store: store).pending(limit: 200).map { item in
            EncryptedChange(id: item.id, envelope: try vault.seal(item.payload, metadata: EnvelopeMetadata(vaultID: vault.id, recordID: UUID(uuidString: item.id)!, entityType: item.entityType, schemaVersion: 1, tombstone: false)))
        }
    }

    @Test func downloadedGoalMustBeMaterializedBeforeReportingUpToDate() async throws {
        let sender = try await device(), receiver = try await device()
        let vault = try Vault.generate(), transport = InMemorySyncTransport(accountFingerprint: Data("A".utf8))
        let id = UUID().uuidString
        try await GoalRepository(store: sender).create(GoalRecord(id: id, title: "Goal", detail: "", status: "active", createdAtMS: 10, updatedAtMS: 10), context: context())
        let outgoing = await SyncCoordinator(store: sender, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual)
        let incoming = await SyncCoordinator(store: receiver, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual)
        #expect(outgoing.state == .upToDate)
        #expect(incoming.state == .upToDate)
        #expect(incoming.downloaded == 1)
        #expect(try await GoalRepository(store: receiver).get(id: id)?.title == "Goal")
    }

    @Test func everyRepositoryEntityAndNullableClearConvergesAfterRelaunch() async throws {
        let sender = try await device(), receiver = try await device(), vault = try Vault.generate()
        let transport = InMemorySyncTransport(accountFingerprint: Data("A".utf8))
        let conversationID = UUID().uuidString, messageID = UUID().uuidString
        let goalID = UUID().uuidString, milestoneID = UUID().uuidString, actionID = UUID().uuidString, evidenceID = UUID().uuidString
        let memoryID = UUID().uuidString, sourceID = UUID().uuidString
        let conversations = ConversationRepository(store: sender), goals = GoalRepository(store: sender)
        let actions = ActionRepository(store: sender), evidence = EvidenceRepository(store: sender), memory = MemoryRepository(store: sender)
        try await conversations.create(ConversationRecord(id: conversationID, title: "Chat", createdAtMS: 1, updatedAtMS: 1), context: context())
        try await conversations.createMessage(MessageRecord(id: messageID, conversationID: conversationID, role: "user", body: "Body", createdAtMS: 2), context: context(time: 2))
        try await goals.create(GoalRecord(id: goalID, title: "Goal", detail: "Detail", status: "active", createdAtMS: 1, updatedAtMS: 1), context: context())
        try await goals.createMilestone(MilestoneRecord(id: milestoneID, goalID: goalID, title: "Step", status: "open", targetAtMS: 20, updatedAtMS: 2), context: context(time: 2))
        try await actions.create(ActionRecord(id: actionID, goalID: goalID, title: "Act", detail: "Do", status: "open", dueAtMS: 20, createdAtMS: 1, updatedAtMS: 2), context: context(time: 2))
        try await evidence.create(EvidenceRecord(id: evidenceID, goalID: goalID, actionID: actionID, title: "Proof", detail: "Details", occurredAtMS: 2, createdAtMS: 1), context: context(time: 2))
        try await memory.create(MemoryRecord(id: memoryID, kind: "fact", content: "Memory", status: "active", createdAtMS: 1, updatedAtMS: 1), context: context())
        try await memory.createSource(MemorySourceRecord(id: sourceID, memoryItemID: memoryID, sourceType: "conversation", sourceID: conversationID, createdAtMS: 2), context: context(time: 2))
        #expect(await SyncCoordinator(store: sender, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual).state == .upToDate)
        #expect(await SyncCoordinator(store: receiver, vault: vault, transport: transport, nowMS: { 101 }).synchronize(reason: .manual).state == .upToDate)
        #expect(try await ConversationRepository(store: receiver).get(id: conversationID)?.createdAtMS == 1)
        #expect(try await ConversationRepository(store: receiver).message(id: messageID)?.body == "Body")
        #expect(try await GoalRepository(store: receiver).get(id: goalID)?.title == "Goal")
        #expect(try await GoalRepository(store: receiver).milestone(id: milestoneID)?.targetAtMS == 20)
        #expect(try await ActionRepository(store: receiver).get(id: actionID)?.goalID == goalID)
        #expect(try await EvidenceRepository(store: receiver).get(id: evidenceID)?.actionID == actionID)
        #expect(try await MemoryRepository(store: receiver).get(id: memoryID)?.content == "Memory")
        #expect(try await MemoryRepository(store: receiver).source(id: sourceID)?.memoryItemID == memoryID)
        try await goals.updateMilestone(MilestoneRecord(id: milestoneID, goalID: goalID, title: "Step", status: "open", targetAtMS: nil, updatedAtMS: 3), context: context(time: 3))
        try await actions.update(ActionRecord(id: actionID, goalID: nil, title: "Act", detail: "Do", status: "open", dueAtMS: nil, createdAtMS: 1, updatedAtMS: 3), context: context(time: 3))
        try await evidence.update(EvidenceRecord(id: evidenceID, goalID: nil, actionID: nil, title: "Proof", detail: "Details", occurredAtMS: 3, createdAtMS: 1), context: context(time: 3))
        #expect(await SyncCoordinator(store: sender, vault: vault, transport: transport, nowMS: { 200 }).synchronize(reason: .manual).state == .upToDate)
        #expect(await SyncCoordinator(store: receiver, vault: vault, transport: transport, nowMS: { 201 }).synchronize(reason: .manual).state == .upToDate)
        #expect(try await GoalRepository(store: receiver).milestone(id: milestoneID)?.targetAtMS == nil)
        #expect(try await ActionRepository(store: receiver).get(id: actionID)?.goalID == nil)
        #expect(try await ActionRepository(store: receiver).get(id: actionID)?.dueAtMS == nil)
        #expect(try await EvidenceRepository(store: receiver).get(id: evidenceID)?.goalID == nil)
        #expect(try await EvidenceRepository(store: receiver).get(id: evidenceID)?.actionID == nil)
        #expect(await SyncCoordinator(store: receiver, vault: vault, transport: transport, nowMS: { 202 }).synchronize(reason: .foreground).state == .upToDate)
    }

    @Test func childBeforeParentPageWaitsForAtomicMaterialization() async throws {
        let sender = try await device(), receiver = try await device(), vault = try Vault.generate()
        let parent = UUID().uuidString, child = UUID().uuidString
        let repo = ConversationRepository(store: sender)
        try await repo.create(ConversationRecord(id: parent, title: "Parent", createdAtMS: 1, updatedAtMS: 1), context: context())
        try await repo.createMessage(MessageRecord(id: child, conversationID: parent, role: "user", body: "Child", createdAtMS: 2), context: context(time: 2))
        let envelopes = try await changes(sender, vault)
        let transport = ReviewTransport()
        await transport.configure(pages: [SyncFetchPage(changes: [envelopes[1]], token: Data("child".utf8), hasMore: true), SyncFetchPage(changes: [envelopes[0]], token: Data("parent".utf8))])
        let outcome = await SyncCoordinator(store: receiver, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual)
        #expect(outcome.state == .upToDate)
        #expect(try await ConversationRepository(store: receiver).message(id: child)?.body == "Child")
        let token = try await receiver.read { db in try Data.fetchOne(db, sql: "SELECT change_token FROM sync_state WHERE id = 1") }
        #expect(token == Data("parent".utf8))
    }

    @Test func updateWithoutItsCreateCannotAdvanceTokenOrClaimSuccess() async throws {
        let sender = try await device(), receiver = try await device(), vault = try Vault.generate()
        let id = UUID().uuidString, dev = UUID().uuidString
        try await ProfileRepository(store: sender).create(profile(id, "Base"), context: context(dev))
        try await ProfileRepository(store: sender).update(profile(id, "Update", time: 11), context: context(dev, time: 11))
        let envelopes = try await changes(sender, vault)
        let transport = ReviewTransport()
        await transport.configure(pages: [SyncFetchPage(changes: [envelopes[1]], token: Data("orphan".utf8))])
        let outcome = await SyncCoordinator(store: receiver, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual)
        #expect(outcome.state == .recoveryRequired)
        #expect(try await ProfileRepository(store: receiver).get(id: id) == nil)
        let token = try await receiver.read { db in try Data.fetchOne(db, sql: "SELECT change_token FROM sync_state WHERE id = 1") }
        #expect(token == nil)
    }

    @Test func clearingNullableFieldMustNotQuarantineValidLocalMutation() async throws {
        let store = try await device(), vault = try Vault.generate()
        let transport = InMemorySyncTransport(accountFingerprint: Data("A".utf8))
        let coordinator = SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 100 })
        let id = UUID().uuidString, dev = UUID().uuidString
        let repo = ActionRepository(store: store)
        try await repo.create(ActionRecord(id: id, goalID: nil, title: "Action", detail: "", status: "open", dueAtMS: 20, createdAtMS: 10, updatedAtMS: 10), context: context(dev))
        _ = await coordinator.synchronize(reason: .manual)
        try await repo.update(ActionRecord(id: id, goalID: nil, title: "Action", detail: "", status: "open", dueAtMS: nil, createdAtMS: 10, updatedAtMS: 11), context: context(dev, time: 11))
        let outcome = await coordinator.synchronize(reason: .manual)
        #expect(outcome.state == .upToDate)
        #expect(outcome.quarantined == 0)
    }

    @Test func reorderedRemoteHistoryMustBecomeCorrectParentOfNextLocalEdit() async throws {
        let sender = try await device(), receiver = try await device(), vault = try Vault.generate()
        let id = UUID().uuidString, dev = UUID().uuidString
        try await ProfileRepository(store: sender).create(profile(id, "Base"), context: context(dev))
        let update = context(dev, time: 11)
        try await ProfileRepository(store: sender).update(profile(id, "Remote", time: 11), context: update)
        let envelopes = try await changes(sender, vault)
        let transport = ReviewTransport()
        await transport.configure(pages: [SyncFetchPage(changes: [envelopes[1]], token: Data("1".utf8), hasMore: true), SyncFetchPage(changes: [envelopes[0]], token: Data("2".utf8))])
        let coordinator = SyncCoordinator(store: receiver, vault: vault, transport: transport, nowMS: { 100 })
        #expect(await coordinator.synchronize(reason: .manual).state == .upToDate)
        #expect(try await ProfileRepository(store: receiver).get(id: id)?.displayName == "Remote")
        let next = context(time: 12)
        try await ProfileRepository(store: receiver).update(profile(id, "Local", time: 12), context: next)
        let local = try #require(await ChangeJournal(store: receiver).pending(limit: 10).first)
        struct Payload: Decodable { let causality: CausalSnapshot }
        let causal = try JSONDecoder().decode(Payload.self, from: local.payload).causality
        #expect(causal.changedFields.first { $0.fieldName == "displayName" }?.parentVersionID == update.id)
    }

    @Test func orderedReversedAndDuplicatedHistoryKeepsTheSameLocalParent() async throws {
        let sender = try await device(), vault = try Vault.generate()
        let id = UUID().uuidString, dev = UUID().uuidString
        try await ProfileRepository(store: sender).create(profile(id, "Base"), context: context(dev))
        let update = context(dev, time: 11)
        try await ProfileRepository(store: sender).update(profile(id, "Remote", time: 11), context: update)
        let envelopes = try await changes(sender, vault)
        for ordering in [[0, 1], [1, 0], [1, 1, 0]] {
            let receiver = try await device(), transport = ReviewTransport()
            await transport.configure(pages: [SyncFetchPage(changes: ordering.map { envelopes[$0] }, token: Data("done".utf8))])
            #expect(await SyncCoordinator(store: receiver, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual).state == .upToDate)
            try await ProfileRepository(store: receiver).update(profile(id, "Local", time: 12), context: context(time: 12))
            let local = try #require(await ChangeJournal(store: receiver).pending(limit: 10).first)
            #expect(local.causality.changedFields.first { $0.fieldName == "displayName" }?.parentVersionID == update.id)
        }
    }

    @Test func remoteTombstoneMustNotDuplicateLocalTombstoneAndResurrectRecord() async throws {
        let store = try await device(), vault = try Vault.generate()
        let transport = InMemorySyncTransport(accountFingerprint: Data("A".utf8))
        let id = UUID().uuidString, dev = UUID().uuidString
        let repo = ProfileRepository(store: store)
        try await repo.create(profile(id, "Deleted"), context: context(dev))
        try await repo.delete(id: id, context: context(dev, time: 11))
        #expect(try await repo.get(id: id) == nil)
        let coordinator = SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 100 })
        #expect(await coordinator.synchronize(reason: .manual).state == .upToDate)
        #expect(try await repo.get(id: id) == nil)
        let count = try await store.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tombstones WHERE entity_id = ?", arguments: [id]) }
        #expect(count == 1)
    }

    @Test func repeatedThrownNetworkFailuresMustIncreaseBackoff() async throws {
        let store = try await device(), vault = try Vault.generate(), transport = ReviewTransport()
        await transport.configure(failSend: true)
        try await ProfileRepository(store: store).create(profile(UUID().uuidString, "Pending"), context: context())
        let first = await SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 1_000 }).synchronize(reason: .manual)
        let second = await SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 10_000 }).synchronize(reason: .manual)
        #expect((second.retryAtMS ?? 0) - 10_000 > (first.retryAtMS ?? 0) - 1_000)
    }

    @Test func partialRetryDeadlinesUseLatestServerLimitAndResetAfterProgress() async throws {
        let store = try await device(), vault = try Vault.generate()
        let transport = InMemorySyncTransport(accountFingerprint: Data("A".utf8))
        let repo = ProfileRepository(store: store)
        let first = context(), second = context(), third = context()
        try await repo.create(profile(UUID().uuidString, "One"), context: first)
        try await repo.create(profile(UUID().uuidString, "Two"), context: second)
        await transport.failNextItems([first.id: .rateLimited(retryAfterMS: 5_000), second.id: .rateLimited(retryAfterMS: 9_000)])
        let delayed = await SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual)
        #expect(delayed.state == .retrying)
        #expect(delayed.retryAtMS == 9_000)
        #expect(await SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 8_000 }).synchronize(reason: .manual).retryAtMS == 9_000)
        #expect(await SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 10_000 }).synchronize(reason: .manual).state == .upToDate)
        try await repo.create(profile(UUID().uuidString, "Three"), context: third)
        await transport.failNextSend(.retryable)
        let fresh = await SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 20_000 }).synchronize(reason: .manual)
        #expect(fresh.retryAtMS == 21_000)
    }

    @Test func accountGenerationRejectsReturnToOldAndMidFetchChange() async throws {
        let store = try await device(), vault = try Vault.generate()
        let transport = InMemorySyncTransport(accountFingerprint: Data("A".utf8))
        let old = try await transport.bind(expectedFingerprint: Data("A".utf8))
        await transport.setAccountFingerprint(Data("B".utf8))
        await transport.setAccountFingerprint(Data("A".utf8))
        await #expect(throws: SyncTransportError.accountChanged) {
            try await transport.send([], session: old)
        }
        await transport.changeAccountAfterNextFetch(to: Data("B".utf8))
        let outcome = await SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual)
        #expect(outcome.state == .accountChanged)
        let token = try await store.read { db in try Data.fetchOne(db, sql: "SELECT change_token FROM sync_state WHERE id = 1") }
        #expect(token == nil)
    }

    @Test func accountSwitchAtTransportBoundaryMustNotSendToDifferentAccount() async throws {
        let store = try await device(), vault = try Vault.generate(), transport = ReviewTransport()
        await transport.configure(switchOnSend: true)
        try await ProfileRepository(store: store).create(profile(UUID().uuidString, "Private"), context: context())
        #expect(await SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual).state == .accountChanged)
        #expect(await transport.sentAccounts.isEmpty)
    }

    @Test func thousandPageLimitContinuesOnNextTurnWithoutTokenOveradvance() async throws {
        let store = try await device(), vault = try Vault.generate(), transport = ReviewTransport()
        await transport.configure(emptyPages: 1_001)
        let outcome = await SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual)
        #expect(outcome.state == .retrying)
        #expect(await transport.fetchCounter == 1_001)
        let token = try await store.read { db in try Data.fetchOne(db, sql: "SELECT change_token FROM sync_state WHERE id = 1") }
        #expect(token == Data("1000".utf8))
        let resumed = await SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 2_000 }).synchronize(reason: .manual)
        #expect(resumed.state == .upToDate)
        let continued = try await store.read { db in try Data.fetchOne(db, sql: "SELECT change_token FROM sync_state WHERE id = 1") }
        #expect(continued == Data("1001".utf8))
    }

    @Test func authenticatedFutureSchemaMustNotBeAppliedAsVersionOne() async throws {
        let sender = try await device(), receiver = try await device(), vault = try Vault.generate()
        let id = UUID().uuidString
        try await ProfileRepository(store: sender).create(profile(id, "Future"), context: context())
        let item = try #require(await ChangeJournal(store: sender).pending(limit: 10).first)
        let envelope = try vault.seal(item.payload, metadata: EnvelopeMetadata(vaultID: vault.id, recordID: UUID(uuidString: item.id)!, entityType: "profile", schemaVersion: 999, tombstone: false))
        let transport = ReviewTransport()
        await transport.configure(pages: [SyncFetchPage(changes: [EncryptedChange(id: item.id, envelope: envelope)], token: Data("future".utf8))])
        let outcome = await SyncCoordinator(store: receiver, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual)
        #expect(outcome.state == .recoveryRequired)
        #expect(try await ProfileRepository(store: receiver).get(id: id) == nil)
        let token = try await receiver.read { db in try Data.fetchOne(db, sql: "SELECT change_token FROM sync_state WHERE id = 1") }
        #expect(token == nil)
    }

    @Test func resolutionPersistenceFailureMustRemainContentFreeAndAtomic() async throws {
        let first = try await device(), second = try await device(), vault = try Vault.generate()
        let transport = InMemorySyncTransport(accountFingerprint: Data("A".utf8))
        let a = SyncCoordinator(store: first, vault: vault, transport: transport, nowMS: { 100 })
        let b = SyncCoordinator(store: second, vault: vault, transport: transport, nowMS: { 100 })
        let id = UUID().uuidString, ad = UUID().uuidString, bd = UUID().uuidString
        try await ProfileRepository(store: first).create(profile(id, "Base"), context: context(ad))
        _ = await a.synchronize(reason: .manual); _ = await b.synchronize(reason: .manual)
        try await ProfileRepository(store: first).update(profile(id, "One", time: 11), context: context(ad, time: 11))
        try await ProfileRepository(store: second).update(profile(id, "Two", time: 11), context: context(bd, time: 11))
        _ = await a.synchronize(reason: .manual); _ = await b.synchronize(reason: .manual); _ = await a.synchronize(reason: .manual)
        let conflict = try #require(await ConflictStore(store: first).unresolved().first { $0.fieldName == "displayName" })
        let mutation = try conflict.resolve(value: Data("\"Resolved\"".utf8), mutationID: UUID().uuidString, deviceID: UUID().uuidString, counter: 1, timestampMS: 12)
        try await first.write { db in
            try db.execute(sql: "CREATE TRIGGER review_fail_outbox BEFORE INSERT ON outbox BEGIN SELECT RAISE(ABORT, 'PRIVATE-RESOLUTION-CANARY'); END")
        }
        var description = ""
        do { try await a.resolveConflict(conflict, using: mutation); Issue.record("Expected injected failure") }
        catch {
            #expect(error is SyncMergeError)
            description = String(describing: error)
            #expect(!String(reflecting: error).contains("PRIVATE-RESOLUTION-CANARY"))
            #expect(!String(describing: Mirror(reflecting: error)).contains("PRIVATE-RESOLUTION-CANARY"))
        }
        #expect(!description.contains("PRIVATE-RESOLUTION-CANARY"))
        #expect(try await ConflictStore(store: first).unresolved().count == 1)
        #expect(try await ChangeJournal(store: first).pending(limit: 10).isEmpty)
        #expect(try await ProfileRepository(store: first).get(id: id)?.displayName != "Resolved")
    }

    @Test func goalConflictResolutionKeepsImmutableCreationFieldsAcrossDevices() async throws {
        let first = try await device(), second = try await device(), vault = try Vault.generate()
        let transport = InMemorySyncTransport(accountFingerprint: Data("A".utf8))
        let a = SyncCoordinator(store: first, vault: vault, transport: transport, nowMS: { 100 })
        let b = SyncCoordinator(store: second, vault: vault, transport: transport, nowMS: { 100 })
        let id = UUID().uuidString, ad = UUID().uuidString, bd = UUID().uuidString
        try await GoalRepository(store: first).create(GoalRecord(id: id, title: "Base", detail: "Detail", status: "active", createdAtMS: 1, updatedAtMS: 1), context: context(ad))
        _ = await a.synchronize(reason: .manual); _ = await b.synchronize(reason: .manual)
        try await GoalRepository(store: first).update(GoalRecord(id: id, title: "One", detail: "Detail", status: "active", createdAtMS: 1, updatedAtMS: 2), context: context(ad, time: 2))
        try await GoalRepository(store: second).update(GoalRecord(id: id, title: "Two", detail: "Detail", status: "active", createdAtMS: 1, updatedAtMS: 2), context: context(bd, time: 2))
        _ = await a.synchronize(reason: .manual); _ = await b.synchronize(reason: .manual); _ = await a.synchronize(reason: .manual)
        let conflict = try #require(await ConflictStore(store: first).unresolved().first { $0.fieldName == "title" })
        let resolution = try conflict.resolve(value: Data("\"Chosen\"".utf8), mutationID: UUID().uuidString, deviceID: UUID().uuidString, counter: 1, timestampMS: 3)
        try await a.resolveConflict(conflict, using: resolution)
        #expect(try await GoalRepository(store: first).get(id: id)?.createdAtMS == 1)
        _ = await a.synchronize(reason: .manual); _ = await b.synchronize(reason: .manual)
        #expect(try await GoalRepository(store: second).get(id: id)?.title == "Chosen")
        #expect(try await GoalRepository(store: second).get(id: id)?.createdAtMS == 1)
    }

    @Test func overlappingTurnsMustNotRegressDurableToken() async throws {
        let store = try await device(), vault = try Vault.generate(), transport = OverlapTransport()
        let coordinator = SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 100 })
        let first = Task { await coordinator.synchronize(reason: .foreground) }
        await transport.waitForFirst()
        let second = await coordinator.synchronize(reason: .notification)
        #expect(second.state == .upToDate)
        await transport.releaseFirst()
        _ = await first.value
        let token = try await store.read { db in try Data.fetchOne(db, sql: "SELECT change_token FROM sync_state WHERE id = 1") }
        #expect(token == Data("newer".utf8))
    }

    @Test func twoCoordinatorInstancesCannotRegressCursorOrState() async throws {
        let store = try await device(), vault = try Vault.generate(), transport = OverlapTransport()
        let firstCoordinator = SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 100 })
        let secondCoordinator = SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 100 })
        let first = Task { await firstCoordinator.synchronize(reason: .foreground) }
        await transport.waitForFirst()
        #expect(await secondCoordinator.synchronize(reason: .notification).state == .upToDate)
        await transport.releaseFirst()
        #expect(await first.value.state == .upToDate)
        #expect(await firstCoordinator.currentState == .upToDate)
        let token = try await store.read { db in try Data.fetchOne(db, sql: "SELECT change_token FROM sync_state WHERE id = 1") }
        #expect(token == Data("newer".utf8))
    }

    @Test func zoneResetMustNotTurnIntoUpToDateWithoutRecovery() async throws {
        let store = try await device(), vault = try Vault.generate()
        let transport = InMemorySyncTransport(accountFingerprint: Data("A".utf8))
        let coordinator = SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 100 })
        await transport.failNextFetch(.zoneReset)
        #expect(await coordinator.synchronize(reason: .manual).state == .zoneReset)
        let relaunched = SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 101 })
        #expect(await relaunched.synchronize(reason: .foreground).state == .zoneReset)
    }

    @Test func zoneResetReconciliationReplaysAcknowledgedHistoryBeforeClearingRecovery() async throws {
        let store = try await device(), restored = try await device(), vault = try Vault.generate()
        let transport = InMemorySyncTransport(accountFingerprint: Data("A".utf8))
        let id = UUID().uuidString
        try await ProfileRepository(store: store).create(profile(id, "Retained"), context: context())
        #expect(await SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual).state == .upToDate)
        await transport.resetZoneForTesting()
        await transport.failNextFetch(.zoneReset)
        #expect(await SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 200 }).synchronize(reason: .manual).state == .zoneReset)
        let relaunched = SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 300 })
        #expect(await relaunched.synchronize(reason: .foreground).state == .zoneReset)
        #expect(await transport.allChanges().isEmpty)
        await transport.failNextSend(.permission)
        #expect(await relaunched.reconcileZoneAfterReset().state == .zoneReset)
        #expect(await SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 301 }).synchronize(reason: .foreground).state == .zoneReset)
        #expect(await relaunched.reconcileZoneAfterReset().state == .upToDate)
        #expect(await transport.allChanges().count == 1)
        #expect(await SyncCoordinator(store: restored, vault: vault, transport: transport, nowMS: { 400 }).synchronize(reason: .manual).state == .upToDate)
        #expect(try await ProfileRepository(store: restored).get(id: id)?.displayName == "Retained")
    }

    @Test func zoneResetReconciliationAlsoReplaysReceivedOnlyHistory() async throws {
        let origin = try await device(), holder = try await device(), restored = try await device(), vault = try Vault.generate()
        let transport = InMemorySyncTransport(accountFingerprint: Data("A".utf8))
        let id = UUID().uuidString
        try await ProfileRepository(store: origin).create(profile(id, "Remote only"), context: context())
        #expect(await SyncCoordinator(store: origin, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual).state == .upToDate)
        #expect(await SyncCoordinator(store: holder, vault: vault, transport: transport, nowMS: { 101 }).synchronize(reason: .manual).state == .upToDate)
        #expect(try await ChangeJournal(store: holder).pending(limit: 10).isEmpty)
        await transport.resetZoneForTesting()
        await transport.failNextFetch(.zoneReset)
        let coordinator = SyncCoordinator(store: holder, vault: vault, transport: transport, nowMS: { 200 })
        #expect(await coordinator.synchronize(reason: .manual).state == .zoneReset)
        #expect(await coordinator.reconcileZoneAfterReset().state == .upToDate)
        #expect(await transport.allChanges().count == 1)
        #expect(await SyncCoordinator(store: restored, vault: vault, transport: transport, nowMS: { 300 }).synchronize(reason: .manual).state == .upToDate)
        #expect(try await ProfileRepository(store: restored).get(id: id)?.displayName == "Remote only")
    }
}
