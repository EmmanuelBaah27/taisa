import Foundation
import GRDB
import Testing
@testable import TaisaStorage

private actor EntityIdentityKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}

@Suite(.serialized) struct Task3EntityIdentityTests {
    private func fixture() async throws -> (TaisaStore, URL, EntityIdentityKeys) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let keys = EntityIdentityKeys()
        return (try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: keys), directory, keys)
    }

    private func context(_ timestamp: Int64) -> MutationContext {
        MutationContext(id: UUID().uuidString, deviceID: UUID().uuidString, timestamp: timestamp)
    }

    @Test func legacyMemoryParentAllowsSourceCreateReplayAndUpdateWithCausalLineage() async throws {
        let (store, directory, keys) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let memoryID = "ABCDEFAB-1234-4567-89AB-ABCDEFABCDEF"
        let sourceID = "ABCDEFAB-1234-4567-89AB-ABCDEFABCDEA"
        let sourceRowID = "ABCDEFAB-1234-4567-89AB-ABCDEFABCDEB"
        let repository = MemoryRepository(store: store)
        try await repository.create(MemoryRecord(id: memoryID, kind: "fact", content: "A", status: "active", createdAtMS: 100, updatedAtMS: 100), context: context(100))
        try await store.write { db in
            try db.execute(sql: "UPDATE memory_items SET id = ? WHERE id = ?", arguments: [memoryID.lowercased(), memoryID])
        }
        let reopened = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: keys)
        let resumed = MemoryRepository(store: reopened)
        let created = MemorySourceRecord(id: sourceRowID.lowercased(), memoryItemID: memoryID.lowercased(), sourceType: "evidence", sourceID: sourceID.lowercased(), createdAtMS: 101)
        let creation = context(101)
        try await resumed.createSource(created, context: creation)
        try await resumed.createSource(created, context: creation)
        #expect(try await resumed.source(id: sourceRowID)?.memoryItemID == memoryID)
        #expect(try await resumed.source(id: sourceRowID)?.sourceID == sourceID)
        let changed = MemorySourceRecord(id: sourceRowID, memoryItemID: memoryID, sourceType: "message", sourceID: sourceID, createdAtMS: 101)
        let update = context(102)
        try await resumed.updateSource(changed, context: update)
        try await resumed.updateSource(changed, context: update)
        #expect(try await resumed.source(id: sourceRowID)?.sourceType == "message")
        let journal = ChangeJournal(store: reopened)
        let sourceChanges = try await journal.pending(limit: 10).filter { $0.entityType == "memory_source" }
        #expect(sourceChanges.count == 2)
        #expect(sourceChanges[0].causality.changedFields.first { $0.fieldName == "sourceType" }?.versionID == creation.id)
        #expect(sourceChanges[1].causality.changedFields.first { $0.fieldName == "sourceType" }?.parentVersionID == creation.id)
        #expect(try await reopened.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM memory_sources WHERE memory_item_id = ?", arguments: [memoryID.lowercased()]) } == 1)
    }

    @Test func legacySourceTupleCannotForkByUUIDCasing() async throws {
        let (store, directory, keys) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let memoryID = "ABCDEFAB-1234-4567-89AB-ABCDEFABCDEF"
        let sourceID = "ABCDEFAB-1234-4567-89AB-ABCDEFABCDEA"
        let repository = MemoryRepository(store: store)
        try await repository.create(MemoryRecord(id: memoryID, kind: "fact", content: "A", status: "active", createdAtMS: 100, updatedAtMS: 100), context: context(100))
        let original = MemorySourceRecord(id: UUID().uuidString, memoryItemID: memoryID, sourceType: "evidence", sourceID: sourceID, createdAtMS: 101)
        let originalContext = context(101)
        try await repository.createSource(original, context: originalContext)
        try await store.write { db in
            try db.execute(sql: "UPDATE memory_sources SET source_id = ? WHERE id = ?", arguments: [sourceID.lowercased(), original.id])
        }
        let reopened = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: keys)
        let resumed = MemoryRepository(store: reopened)
        try await resumed.createSource(original, context: originalContext)
        let duplicate = MemorySourceRecord(id: UUID().uuidString, memoryItemID: memoryID, sourceType: "evidence", sourceID: sourceID.lowercased(), createdAtMS: 102)
        await #expect(throws: RepositoryError.persistenceFailed) {
            try await resumed.createSource(duplicate, context: context(102))
        }
        #expect(try await reopened.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM memory_sources") } == 1)
        #expect(try await reopened.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM outbox") } == 2)
        #expect(try await reopened.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM field_versions WHERE entity_type = 'memory_source'") } == 4)
    }

    @Test func sourceUpdateCannotCollideWithLegacySemanticTuple() async throws {
        let (store, directory, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let memoryID = UUID().uuidString
        let sourceID = "ABCDEFAB-1234-4567-89AB-ABCDEFABCDEA"
        let repository = MemoryRepository(store: store)
        try await repository.create(MemoryRecord(id: memoryID, kind: "fact", content: "A", status: "active", createdAtMS: 100, updatedAtMS: 100), context: context(100))
        let first = MemorySourceRecord(id: UUID().uuidString, memoryItemID: memoryID, sourceType: "evidence", sourceID: sourceID, createdAtMS: 101)
        let second = MemorySourceRecord(id: UUID().uuidString, memoryItemID: memoryID, sourceType: "message", sourceID: sourceID, createdAtMS: 102)
        try await repository.createSource(first, context: context(101))
        try await repository.createSource(second, context: context(102))
        try await store.write { db in
            try db.execute(sql: "UPDATE memory_sources SET source_id = ? WHERE id = ?", arguments: [sourceID.lowercased(), first.id])
        }
        let collision = MemorySourceRecord(id: second.id, memoryItemID: memoryID, sourceType: "evidence", sourceID: sourceID.lowercased(), createdAtMS: 102)
        await #expect(throws: RepositoryError.persistenceFailed) { try await repository.updateSource(collision, context: context(103)) }
        #expect(try await repository.source(id: second.id) == second)
        #expect(try await ChangeJournal(store: store).pending(limit: 10).count == 3)
    }

    @Test func entityTagMappingMatchesEveryCurrentDomainTableAndReference() async throws {
        let (store, directory, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(DomainEntity.allCases.count == 10)
        for kind in DomainEntity.allCases {
            let valid = try await store.read { db in
                guard try db.tableExists(kind.table),
                      try db.columns(in: kind.table).contains(where: { $0.name == "id" }) else { return false }
                let foreignKeys = try Row.fetchAll(db, sql: "PRAGMA foreign_key_list(\(kind.table))")
                return kind.references.allSatisfy { reference in
                    foreignKeys.contains { row in
                        (row["from"] as String) == reference.column && (row["table"] as String) == reference.table
                    }
                }
            }
            #expect(valid)
        }
    }

    @Test func entityForkWithDistinctMutationIDsCannotBeObservedOrReserved() async throws {
        let (store, directory, keys) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = "ABCDEFAB-1234-4567-89AB-ABCDEFABCDEF"
        let other = "ABCDEFAB-1234-4567-89AB-ABCDEFABCDEA"
        let repository = ProfileRepository(store: store)
        let first = context(100), second = context(101)
        try await repository.create(ProfileRecord(id: id, displayName: "First", headline: "", biography: "", updatedAtMS: 100), context: first)
        try await repository.create(ProfileRecord(id: other, displayName: "Fork", headline: "", biography: "", updatedAtMS: 101), context: second)
        let outgoing = try #require(await ChangeJournal(store: store).pending(limit: 10).last)
        let old = try #require(String(data: outgoing.payload, encoding: .utf8))
        let legacy = Data(old.replacingOccurrences(of: other, with: id.lowercased()).utf8)
        try await store.write { db in
            try db.execute(sql: "UPDATE profile SET id = ? WHERE id = ?", arguments: [id.lowercased(), other])
            try db.execute(sql: "UPDATE outbox SET entity_id = ?, payload = ? WHERE mutation_id = ?", arguments: [id.lowercased(), legacy, second.id])
        }
        let reopened = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: keys)
        let journal = ChangeJournal(store: reopened)
        await #expect(throws: RepositoryError.persistenceFailed) { _ = try await journal.pending(limit: 10) }
        await #expect(throws: RepositoryError.persistenceFailed) { _ = try await journal.reservePending(limit: 10, at: 200, leaseDurationMS: 10) }
        await #expect(throws: RepositoryError.persistenceFailed) { _ = try await journal.state(id: first.id) }
        await #expect(throws: RepositoryError.persistenceFailed) { _ = try await journal.remoteCoverage(id: second.id) }
        await #expect(throws: RepositoryError.persistenceFailed) { try await journal.acknowledge(id: first.id, at: 200) }
        await #expect(throws: RepositoryError.persistenceFailed) { try await journal.retry(id: second.id, category: "offline") }
        #expect(try await reopened.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM outbox WHERE status = 'pending'") } == 2)
    }

    @Test func sameUUIDAcrossDifferentEntityTypesIsNotAnIdentityFork() async throws {
        let (store, directory, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID().uuidString
        try await ProfileRepository(store: store).create(ProfileRecord(id: id, displayName: "A", headline: "", biography: "", updatedAtMS: 100), context: context(100))
        try await GoalRepository(store: store).create(GoalRecord(id: id.lowercased(), title: "B", detail: "", status: "active", createdAtMS: 101, updatedAtMS: 101), context: context(101))
        let outgoing = try await ChangeJournal(store: store).reservePending(limit: 10, at: 200, leaseDurationMS: 10)
        #expect(outgoing.count == 2)
        #expect(Set(outgoing.map { $0.change.entityType }) == ["profile", "goal"])
    }

    @Test func ambiguousReferencedParentCannotReleaseOtherwiseUniqueChild() async throws {
        let (store, directory, keys) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let conversationID = "ABCDEFAB-1234-4567-89AB-ABCDEFABCDEF"
        let otherID = "ABCDEFAB-1234-4567-89AB-ABCDEFABCDEA"
        let repository = ConversationRepository(store: store)
        let first = context(100), second = context(101), child = context(102)
        try await repository.create(ConversationRecord(id: conversationID, title: "First", createdAtMS: 100, updatedAtMS: 100), context: first)
        try await repository.create(ConversationRecord(id: otherID, title: "Fork", createdAtMS: 101, updatedAtMS: 101), context: second)
        try await repository.createMessage(MessageRecord(id: UUID().uuidString, conversationID: conversationID, role: "user", body: "Text", createdAtMS: 102), context: child)
        try await store.write { db in
            try db.execute(sql: "UPDATE conversations SET id = ? WHERE id = ?", arguments: [conversationID.lowercased(), otherID])
            try db.execute(sql: "UPDATE outbox SET status = 'acknowledged', acknowledged_at_ms = 200 WHERE mutation_id IN (?, ?)", arguments: [first.id, second.id])
        }
        let reopened = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: keys)
        let journal = ChangeJournal(store: reopened)
        await #expect(throws: RepositoryError.persistenceFailed) { _ = try await journal.pending(limit: 1) }
        await #expect(throws: RepositoryError.persistenceFailed) { _ = try await journal.reservePending(limit: 1, at: 210, leaseDurationMS: 10) }
        await #expect(throws: RepositoryError.persistenceFailed) { _ = try await journal.state(id: child.id) }
        #expect(try await reopened.read { db in try String.fetchOne(db, sql: "SELECT status FROM outbox WHERE mutation_id = ?", arguments: [child.id]) } == "pending")
    }

    @Test func childDeleteWithoutRecordPayloadStillChecksForkedStoredParent() async throws {
        let (store, directory, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let parent = "ABCDEFAB-1234-4567-89AB-ABCDEFABCDEF"
        let other = "ABCDEFAB-1234-4567-89AB-ABCDEFABCDEA"
        let repository = ConversationRepository(store: store)
        try await repository.create(ConversationRecord(id: parent, title: "First", createdAtMS: 100, updatedAtMS: 100), context: context(100))
        try await repository.create(ConversationRecord(id: other, title: "Other", createdAtMS: 101, updatedAtMS: 101), context: context(101))
        let messageID = UUID().uuidString
        try await repository.createMessage(MessageRecord(id: messageID, conversationID: parent, role: "user", body: "Text", createdAtMS: 102), context: context(102))
        let deletion = context(103)
        try await repository.deleteMessage(id: messageID, context: deletion)
        try await store.write { db in try db.execute(sql: "UPDATE conversations SET id = ? WHERE id = ?", arguments: [parent.lowercased(), other]) }
        let journal = ChangeJournal(store: store)
        await #expect(throws: RepositoryError.persistenceFailed) { _ = try await journal.state(id: deletion.id) }
        await #expect(throws: RepositoryError.persistenceFailed) { _ = try await journal.remoteCoverage(id: deletion.id) }
    }
}
