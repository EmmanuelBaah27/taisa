import Foundation
import GRDB
import Testing
import TaisaStorage
import TaisaSecurity
@testable import TaisaSync

private actor RoundTwoKeys: DatabaseKeyStore {
    var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ value: Data) async throws { key = value }
}
private actor RoundTwoPages: SyncTransport {
    let generation = UUID()
    var pages: [SyncFetchPage] = []
    var errors: [Int: SyncTransportError] = [:]
    var calls = 0
    var cancelAt: Int?
    func accountState() async -> SyncAccountState { .available(fingerprint: Data("A".utf8)) }
    func bind(expectedFingerprint: Data) async throws -> SyncAccountSession { .init(fingerprint: Data("A".utf8), generation: generation) }
    func send(_ changes: [EncryptedChange], session: SyncAccountSession) async throws -> SyncSendResult { .init(acknowledgedIDs: changes.map(\.id)) }
    func configure(_ pages: [SyncFetchPage], errors: [Int: SyncTransportError] = [:], cancelAt: Int? = nil) { self.pages = pages; self.errors = errors; calls = 0; self.cancelAt = cancelAt }
    func fetch(after token: Data?, session: SyncAccountSession) async throws -> SyncFetchPage {
        calls += 1
        if let error = errors[calls] { throw error }
        if calls == cancelAt { withUnsafeCurrentTask { $0?.cancel() } }
        return pages.isEmpty ? .init(changes: [], token: token) : pages.removeFirst()
    }
}

@Suite(.serialized) struct Task6RoundTwoIndependentTests {
    func store() async throws -> TaisaStore {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("round-two-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try await TaisaStore.open(at: dir.appendingPathComponent("store.sqlite"), keyStore: RoundTwoKeys())
    }
    func context(_ id: String = UUID().uuidString) -> MutationContext { .init(id: id, deviceID: UUID().uuidString, timestamp: 10) }
    func changes(_ db: TaisaStore, _ vault: Vault) async throws -> [EncryptedChange] {
        try await ChangeJournal(store: db).pending(limit: 200).map {
            .init(id: $0.id, envelope: try vault.seal($0.payload, metadata: .init(vaultID: vault.id, recordID: UUID(uuidString: $0.id)!, entityType: $0.entityType, schemaVersion: 1, tombstone: false)))
        }
    }

    @Test(arguments: [3, 4, 5]) func equalHeadsAreAllParentsOfLaterEdit(count: Int) async throws {
        let vault = try Vault.generate(), transport = InMemorySyncTransport(accountFingerprint: Data("A".utf8))
        var stores: [TaisaStore] = []
        for _ in 0..<count { stores.append(try await store()) }
        let syncs = stores.map { SyncCoordinator(store: $0, vault: vault, transport: transport, nowMS: { 100 }) }
        let id = UUID().uuidString
        func profile(_ name: String) -> ProfileRecord { .init(id: id, displayName: name, headline: "", biography: "", updatedAtMS: 10) }
        try await ProfileRepository(store: stores[0]).create(profile("Base"), context: context())
        for sync in syncs { #expect(await sync.synchronize(reason: .manual).state == .upToDate) }
        let heads = (1...count).map { String(format: "%08d-1111-4111-8111-%012d", $0, $0) }
        for (index, db) in stores.enumerated() { try await ProfileRepository(store: db).update(profile("Same"), context: context(heads[index])) }
        for sync in syncs { #expect(await sync.synchronize(reason: .manual).state == .upToDate) }
        for sync in syncs { #expect(await sync.synchronize(reason: .manual).state == .upToDate) }
        try await ProfileRepository(store: stores[count - 1]).update(profile("Later"), context: context())
        let pending = try #require(await ChangeJournal(store: stores[count - 1]).pending(limit: 10).first)
        let field = try #require(pending.causality.changedFields.first { $0.fieldName == "displayName" })
        #expect(Set(field.ancestorVersionIDs).isSuperset(of: heads))
        #expect(field.ancestorVersionIDs.first == field.parentVersionID)
        for sync in syncs { #expect(await sync.synchronize(reason: .manual).state == .upToDate) }
        for db in stores { #expect(try await ConflictStore(store: db).unresolved().isEmpty) }
    }

    @Test(arguments: [2, 3, 4, 5]) func deletionAfterEqualValueMergeObservesEveryHead(count: Int) async throws {
        let vault = try Vault.generate(), transport = InMemorySyncTransport(accountFingerprint: Data("A".utf8))
        var stores: [TaisaStore] = []
        for _ in 0..<count { stores.append(try await store()) }
        let syncs = stores.map { SyncCoordinator(store: $0, vault: vault, transport: transport, nowMS: { 100 }) }
        let id = UUID().uuidString
        func profile(_ name: String) -> ProfileRecord { .init(id: id, displayName: name, headline: "", biography: "", updatedAtMS: 10) }
        try await ProfileRepository(store: stores[0]).create(profile("Base"), context: context())
        for sync in syncs { _ = await sync.synchronize(reason: .manual) }
        let heads = (1...count).map { String(format: "%08d-1111-4111-8111-%012d", $0, $0) }
        for (index, db) in stores.enumerated() { try await ProfileRepository(store: db).update(profile("Same"), context: context(heads[index])) }
        for sync in syncs { _ = await sync.synchronize(reason: .manual) }
        for sync in syncs { _ = await sync.synchronize(reason: .manual) }
        try await ProfileRepository(store: stores[count - 1]).delete(id: id, context: context())
        let deletion = try #require(await ChangeJournal(store: stores[count - 1]).pending(limit: 10).first)
        let observed = Set(deletion.causality.observedFieldVersions.filter { $0.fieldName == "displayName" }.map(\.versionID))
        #expect(observed.isSuperset(of: heads))
        #expect(await syncs[count - 1].synchronize(reason: .manual).state == .upToDate)
        for index in 0..<(count - 1) { #expect(await syncs[index].synchronize(reason: .manual).state == .upToDate) }
        for db in stores {
            #expect(try await ConflictStore(store: db).unresolved().isEmpty)
            #expect(try await ProfileRepository(store: db).get(id: id) == nil)
        }
    }

    @Test(arguments: ["message", "memory_source"]) func stableIDDuplicateCreateThenDeleteHasNoFalseConflict(entity: String) async throws {
        let vault = try Vault.generate(), transport = InMemorySyncTransport(accountFingerprint: Data("A".utf8))
        let a = try await store(), b = try await store()
        let sa = SyncCoordinator(store: a, vault: vault, transport: transport, nowMS: { 100 })
        let sb = SyncCoordinator(store: b, vault: vault, transport: transport, nowMS: { 100 })
        let parent = UUID().uuidString, id = UUID().uuidString
        if entity == "message" {
            try await ConversationRepository(store: a).create(.init(id: parent, title: "Chat", createdAtMS: 10, updatedAtMS: 10), context: context())
        } else {
            try await MemoryRepository(store: a).create(.init(id: parent, kind: "fact", content: "Memory", status: "active", createdAtMS: 10, updatedAtMS: 10), context: context())
        }
        _ = await sa.synchronize(reason: .manual); _ = await sb.synchronize(reason: .manual)
        let sourceID = UUID().uuidString
        for db in [a, b] {
            if entity == "message" {
                try await ConversationRepository(store: db).createMessage(.init(id: id, conversationID: parent, role: "user", body: "Same", createdAtMS: 10), context: context())
            } else {
                try await MemoryRepository(store: db).createSource(.init(id: id, memoryItemID: parent, sourceType: "note", sourceID: sourceID, createdAtMS: 10), context: context())
            }
        }
        #expect(await sa.synchronize(reason: .manual).state == .upToDate)
        #expect(await sb.synchronize(reason: .manual).state == .upToDate)
        #expect(await sa.synchronize(reason: .manual).state == .upToDate)
        if entity == "message" { try await ConversationRepository(store: b).deleteMessage(id: id, context: context()) }
        else { try await MemoryRepository(store: b).deleteSource(id: id, context: context()) }
        #expect(await sb.synchronize(reason: .manual).state == .upToDate)
        #expect(await sa.synchronize(reason: .manual).state == .upToDate)
        #expect(try await ConflictStore(store: a).unresolved().isEmpty)
    }

    @Test func explicitRecoveryHonorsPersistedServerDeadline() async throws {
        let db = try await store(), vault = try Vault.generate(), transport = InMemorySyncTransport(accountFingerprint: Data("A".utf8))
        try await ProfileRepository(store: db).create(.init(id: UUID().uuidString, displayName: "Local", headline: "", biography: "", updatedAtMS: 10), context: context())
        let initial = SyncCoordinator(store: db, vault: vault, transport: transport, nowMS: { 100 })
        #expect(await initial.synchronize(reason: .manual).state == .upToDate)
        await transport.resetZoneForTesting(); await transport.failNextFetch(.zoneReset)
        #expect(await initial.synchronize(reason: .manual).state == .zoneReset)
        await transport.failNextSend(.rateLimited(retryAfterMS: 9000))
        #expect(await initial.reconcileZoneAfterReset().state == .zoneReset)
        let encoded = try #require(await db.read { try Data.fetchOne($0, sql: "SELECT engine_state FROM sync_state WHERE id=1") })
        #expect(try JSONDecoder().decode(SyncEngineCheckpoint.self, from: encoded).retryAtMS == 9000)
        let retry = await SyncCoordinator(store: db, vault: vault, transport: transport, nowMS: { 200 }).reconcileZoneAfterReset()
        #expect(retry.uploaded == 0)
        #expect(retry.state == .zoneReset)
        #expect(await transport.allChanges().isEmpty)
    }

    @Test func explicitRecoveryMixedPartialFailureKeepsLatestDeadline() async throws {
        let db = try await store(), vault = try Vault.generate(), transport = InMemorySyncTransport(accountFingerprint: Data("A".utf8))
        let first = context(), second = context()
        let repo = ProfileRepository(store: db)
        try await repo.create(.init(id: UUID().uuidString, displayName: "One", headline: "", biography: "", updatedAtMS: 10), context: first)
        try await repo.create(.init(id: UUID().uuidString, displayName: "Two", headline: "", biography: "", updatedAtMS: 10), context: second)
        let sync = SyncCoordinator(store: db, vault: vault, transport: transport, nowMS: { 100 })
        #expect(await sync.synchronize(reason: .manual).state == .upToDate)
        await transport.resetZoneForTesting()
        await transport.failNextFetch(.zoneReset)
        #expect(await sync.synchronize(reason: .manual).state == .zoneReset)
        await transport.failNextItems([first.id: .quota, second.id: .rateLimited(retryAfterMS: 9000)])
        let failed = await sync.reconcileZoneAfterReset()
        #expect(failed.state == .zoneReset)
        #expect(failed.retryAtMS == 9000)
        let early = await SyncCoordinator(store: db, vault: vault, transport: transport, nowMS: { 200 }).reconcileZoneAfterReset()
        #expect(early.state == .zoneReset)
        #expect(early.retryAtMS == 9000)
        #expect(early.uploaded == 0)
        #expect(await transport.allChanges().isEmpty)
        #expect(await SyncCoordinator(store: db, vault: vault, transport: transport, nowMS: { 9000 }).reconcileZoneAfterReset().state == .upToDate)
    }

    @Test func explicitRecoveryFetchBackoffBlocksEarlyRetry() async throws {
        let db = try await store(), vault = try Vault.generate(), transport = RoundTwoPages()
        await transport.configure([], errors: [1: .zoneReset])
        let sync = SyncCoordinator(store: db, vault: vault, transport: transport, nowMS: { 100 })
        #expect(await sync.synchronize(reason: .manual).state == .zoneReset)
        await transport.configure([], errors: [1: .retryable])
        let failed = await sync.reconcileZoneAfterReset()
        #expect(failed.state == .zoneReset)
        #expect(failed.retryAtMS == 1100)
        let early = await SyncCoordinator(store: db, vault: vault, transport: transport, nowMS: { 200 }).reconcileZoneAfterReset()
        #expect(early.state == .zoneReset)
        #expect(early.retryAtMS == 1100)
        #expect(await transport.calls == 1)
        await transport.configure([.init(changes: [], token: Data("done".utf8))])
        #expect(await SyncCoordinator(store: db, vault: vault, transport: transport, nowMS: { 1100 }).reconcileZoneAfterReset().state == .upToDate)
    }

    @Test func deletionRejectsCaseEquivalentDuplicateObservation() throws {
        let version = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let deletion = SyncMutation(id: UUID().uuidString, entityType: "profile", entityID: UUID().uuidString,
            entityVersion: 1, deviceID: UUID().uuidString, counter: 1, timestampMS: 10, kind: .delete,
            fields: [], observedFieldVersions: [
                .init(name: "displayName", versionID: version),
                .init(name: "displayName", versionID: version.uppercased()),
            ])
        #expect(throws: SyncMergeError.self) { try MergeEngine.reduce(events: [deletion]) }
    }

    @Test func equalMemorySourceCreatesSupportLaterEditAfterRelaunch() async throws {
        let vault = try Vault.generate(), transport = InMemorySyncTransport(accountFingerprint: Data("A".utf8))
        let a = try await store(), b = try await store()
        let sa = SyncCoordinator(store: a, vault: vault, transport: transport, nowMS: { 100 })
        let sb = SyncCoordinator(store: b, vault: vault, transport: transport, nowMS: { 100 })
        let parent = UUID().uuidString, id = UUID().uuidString, source = UUID().uuidString
        try await MemoryRepository(store: a).create(.init(id: parent, kind: "fact", content: "Memory", status: "active", createdAtMS: 10, updatedAtMS: 10), context: context())
        _ = await sa.synchronize(reason: .manual); _ = await sb.synchronize(reason: .manual)
        let heads = ["11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222"]
        for (i, db) in [a, b].enumerated() {
            try await MemoryRepository(store: db).createSource(.init(id: id, memoryItemID: parent, sourceType: "note", sourceID: source, createdAtMS: 10), context: context(heads[i]))
        }
        _ = await sa.synchronize(reason: .manual); _ = await sb.synchronize(reason: .manual); _ = await sa.synchronize(reason: .manual)
        try await MemoryRepository(store: b).updateSource(.init(id: id, memoryItemID: parent, sourceType: "later", sourceID: source, createdAtMS: 10), context: context())
        let next = try #require(await ChangeJournal(store: b).pending(limit: 10).first)
        let field = try #require(next.causality.changedFields.first { $0.fieldName == "sourceType" })
        #expect(Set(field.ancestorVersionIDs).isSuperset(of: heads))
        #expect(field.ancestorVersionIDs.first == field.parentVersionID)
        #expect(await SyncCoordinator(store: b, vault: vault, transport: transport, nowMS: { 2000 }).synchronize(reason: .manual).state == .upToDate)
        #expect(await sa.synchronize(reason: .manual).state == .upToDate)
        #expect(try await MemoryRepository(store: a).source(id: id)?.sourceType == "later")
    }

    @Test func recoveryResumesCommittedCursorAfterCancellation() async throws {
        let db = try await store(), vault = try Vault.generate(), transport = RoundTwoPages()
        await transport.configure([], errors: [1: .zoneReset])
        let sync = SyncCoordinator(store: db, vault: vault, transport: transport, nowMS: { 100 })
        #expect(await sync.synchronize(reason: .manual).state == .zoneReset)
        await transport.configure([.init(changes: [], token: Data("1".utf8), hasMore: true), .init(changes: [], token: Data("2".utf8))], cancelAt: 2)
        let task = Task { await sync.reconcileZoneAfterReset() }
        #expect(await task.value.state == .zoneReset)
        #expect(try await db.read { try Data.fetchOne($0, sql: "SELECT change_token FROM sync_state WHERE id=1") } == Data("1".utf8))
        await transport.configure([.init(changes: [], token: Data("2".utf8))])
        #expect(await SyncCoordinator(store: db, vault: vault, transport: transport, nowMS: { 2000 }).reconcileZoneAfterReset().state == .upToDate)
    }

    @Test(arguments: [false, true]) func memorySourceMutationBeforeCreationPageDefersOrTombstones(deletion: Bool) async throws {
        let sender = try await store(), receiver = try await store(), vault = try Vault.generate(), transport = RoundTwoPages()
        let memoryID = UUID().uuidString, sourceID = UUID().uuidString
        let repo = MemoryRepository(store: sender)
        try await repo.create(.init(id: memoryID, kind: "fact", content: "Memory", status: "active", createdAtMS: 10, updatedAtMS: 10), context: context())
        let parent = try await changes(sender, vault)
        await transport.configure([.init(changes: parent, token: Data("1".utf8))])
        let sync = SyncCoordinator(store: receiver, vault: vault, transport: transport, nowMS: { 100 })
        #expect(await sync.synchronize(reason: .manual).state == .upToDate)
        let source = MemorySourceRecord(id: sourceID, memoryItemID: memoryID, sourceType: "note", sourceID: UUID().uuidString, createdAtMS: 10)
        try await repo.createSource(source, context: context())
        if deletion { try await repo.deleteSource(id: sourceID, context: context()) }
        else { try await repo.updateSource(.init(id: sourceID, memoryItemID: memoryID, sourceType: "other", sourceID: source.sourceID, createdAtMS: 10), context: context()) }
        let pending = try await ChangeJournal(store: sender).pending(limit: 10)
        let all = try pending.map { item in
            EncryptedChange(id: item.id, envelope: try vault.seal(item.payload, metadata: .init(vaultID: vault.id, recordID: UUID(uuidString: item.id)!, entityType: item.entityType, schemaVersion: 1, tombstone: deletion && item.id == pending[2].id)))
        }
        await transport.configure([.init(changes: [all[2]], token: Data("2".utf8), hasMore: true), .init(changes: [all[1]], token: Data("3".utf8))])
        #expect(await sync.synchronize(reason: .manual).state == .upToDate)
        #expect(await transport.calls == 2)
        #expect(try await receiver.read { try Data.fetchOne($0, sql: "SELECT change_token FROM sync_state WHERE id=1") } == Data("3".utf8))
        if deletion { #expect(try await MemoryRepository(store: receiver).source(id: sourceID) == nil) }
        else { #expect(try await MemoryRepository(store: receiver).source(id: sourceID)?.sourceType == "other") }
    }

    @Test(arguments: [false, true]) func interruptedMemorySourceBeforeCreateResumesAfterRelaunch(deletion: Bool) async throws {
        let sender = try await store(), receiver = try await store(), vault = try Vault.generate(), transport = RoundTwoPages()
        let memoryID = UUID().uuidString, sourceID = UUID().uuidString
        let repo = MemoryRepository(store: sender)
        try await repo.create(.init(id: memoryID, kind: "fact", content: "Memory", status: "active", createdAtMS: 10, updatedAtMS: 10), context: context())
        await transport.configure([.init(changes: try await changes(sender, vault), token: Data("1".utf8))])
        #expect(await SyncCoordinator(store: receiver, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual).state == .upToDate)
        let source = MemorySourceRecord(id: sourceID, memoryItemID: memoryID, sourceType: "note", sourceID: UUID().uuidString, createdAtMS: 10)
        try await repo.createSource(source, context: context())
        if deletion { try await repo.deleteSource(id: sourceID, context: context()) }
        else { try await repo.updateSource(.init(id: sourceID, memoryItemID: memoryID, sourceType: "other", sourceID: source.sourceID, createdAtMS: 10), context: context()) }
        let pending = try await ChangeJournal(store: sender).pending(limit: 10)
        let all = try pending.map { item in
            EncryptedChange(id: item.id, envelope: try vault.seal(item.payload, metadata: .init(vaultID: vault.id, recordID: UUID(uuidString: item.id)!, entityType: item.entityType, schemaVersion: 1, tombstone: deletion && item.id == pending[2].id)))
        }
        let early = SyncFetchPage(changes: [all[2]], token: Data("2".utf8), hasMore: true)
        await transport.configure([early], errors: [2: .retryable])
        #expect(await SyncCoordinator(store: receiver, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual).state == .retrying)
        let committed = try await receiver.read { try Data.fetchOne($0, sql: "SELECT change_token FROM sync_state WHERE id=1") }
        #expect(committed == Data(deletion ? "2".utf8 : "1".utf8))
        let creation = SyncFetchPage(changes: [all[1]], token: Data("3".utf8))
        await transport.configure(deletion ? [creation] : [early, creation])
        #expect(await SyncCoordinator(store: receiver, vault: vault, transport: transport, nowMS: { 2000 }).synchronize(reason: .manual).state == .upToDate)
        #expect(try await receiver.read { try Data.fetchOne($0, sql: "SELECT change_token FROM sync_state WHERE id=1") } == Data("3".utf8))
        if deletion { #expect(try await MemoryRepository(store: receiver).source(id: sourceID) == nil) }
        else { #expect(try await MemoryRepository(store: receiver).source(id: sourceID)?.sourceType == "other") }
    }

    @Test func interruptedDeferredRelationshipPreservesTokenAndResumesAfterRelaunch() async throws {
        let sender = try await store(), receiver = try await store(), vault = try Vault.generate(), transport = RoundTwoPages()
        let id = UUID().uuidString, goal = UUID().uuidString
        let repo = ActionRepository(store: sender)
        try await repo.create(.init(id: id, goalID: nil, title: "Action", detail: "", status: "open", dueAtMS: nil, createdAtMS: 10, updatedAtMS: 10), context: context())
        let first = try await changes(sender, vault)
        await transport.configure([.init(changes: first, token: Data("1".utf8))])
        #expect(await SyncCoordinator(store: receiver, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual).state == .upToDate)
        try await GoalRepository(store: sender).create(.init(id: goal, title: "Goal", detail: "", status: "active", createdAtMS: 11, updatedAtMS: 11), context: context())
        try await repo.update(.init(id: id, goalID: goal, title: "Action", detail: "", status: "open", dueAtMS: nil, createdAtMS: 10, updatedAtMS: 12), context: context())
        let all = try await changes(sender, vault)
        let update = SyncFetchPage(changes: [all[2]], token: Data("2".utf8), hasMore: true)
        await transport.configure([update], errors: [2: .retryable])
        #expect(await SyncCoordinator(store: receiver, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual).state == .retrying)
        #expect(try await receiver.read { try Data.fetchOne($0, sql: "SELECT change_token FROM sync_state WHERE id=1") } == Data("1".utf8))
        #expect(try await ActionRepository(store: receiver).get(id: id)?.goalID == nil)
        await transport.configure([update, .init(changes: [all[1]], token: Data("3".utf8))])
        #expect(await SyncCoordinator(store: receiver, vault: vault, transport: transport, nowMS: { 2000 }).synchronize(reason: .manual).state == .upToDate)
        #expect(try await ActionRepository(store: receiver).get(id: id)?.goalID == goal)
    }
}
