import Foundation
import GRDB
import Testing
@testable import TaisaStorage

private actor RepositoryKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}

private protocol ContractRepository: Sendable {
    associatedtype Record: DomainRecord
    init(store: TaisaStore)
    func get(id: String) async throws -> Record?
    func create(_ record: Record, context: MutationContext) async throws
    func update(_ record: Record, context: MutationContext) async throws
    func delete(id: String, context: MutationContext) async throws
}
extension ProfileRepository: ContractRepository { typealias Record = ProfileRecord }
extension ConversationRepository: ContractRepository { typealias Record = ConversationRecord }
extension GoalRepository: ContractRepository { typealias Record = GoalRecord }
extension ActionRepository: ContractRepository { typealias Record = ActionRecord }
extension EvidenceRepository: ContractRepository { typealias Record = EvidenceRecord }
extension MemoryRepository: ContractRepository { typealias Record = MemoryRecord }

private struct MessageAdapter: ContractRepository {
    let repository: ConversationRepository
    init(store: TaisaStore) { repository = ConversationRepository(store: store) }
    init(repository: ConversationRepository) { self.repository = repository }
    func get(id: String) async throws -> MessageRecord? { try await repository.message(id: id) }
    func create(_ record: MessageRecord, context: MutationContext) async throws { try await repository.createMessage(record, context: context) }
    func update(_ record: MessageRecord, context: MutationContext) async throws { throw RepositoryError.immutableRecord }
    func delete(id: String, context: MutationContext) async throws { try await repository.deleteMessage(id: id, context: context) }
}
private struct MilestoneAdapter: ContractRepository {
    let repository: GoalRepository
    init(store: TaisaStore) { repository = GoalRepository(store: store) }
    init(repository: GoalRepository) { self.repository = repository }
    func get(id: String) async throws -> MilestoneRecord? { try await repository.milestone(id: id) }
    func create(_ record: MilestoneRecord, context: MutationContext) async throws { try await repository.createMilestone(record, context: context) }
    func update(_ record: MilestoneRecord, context: MutationContext) async throws { try await repository.updateMilestone(record, context: context) }
    func delete(id: String, context: MutationContext) async throws { try await repository.deleteMilestone(id: id, context: context) }
}
private struct SourceAdapter: ContractRepository {
    let repository: MemoryRepository
    init(store: TaisaStore) { repository = MemoryRepository(store: store) }
    init(repository: MemoryRepository) { self.repository = repository }
    func get(id: String) async throws -> MemorySourceRecord? { try await repository.source(id: id) }
    func create(_ record: MemorySourceRecord, context: MutationContext) async throws { try await repository.createSource(record, context: context) }
    func update(_ record: MemorySourceRecord, context: MutationContext) async throws { try await repository.updateSource(record, context: context) }
    func delete(id: String, context: MutationContext) async throws { try await repository.deleteSource(id: id, context: context) }
}

enum RepositoryCase: String, CaseIterable, Sendable {
    case profile, conversation, message, goal, milestone, action, evidence, memory, source
}

@Suite(.serialized) struct RepositoryContractTests {
    @Test func publicRepositoryContractIsTransportNeutral() async throws {
        func accepts<R: DomainRepository>(_ repository: R) { _ = repository }
        func acceptsMessages<R: MessageRepositoryContract>(_ repository: R) { _ = repository }
        func acceptsMilestones<R: MilestoneRepositoryContract>(_ repository: R) { _ = repository }
        func acceptsSources<R: MemorySourceRepositoryContract>(_ repository: R) { _ = repository }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: RepositoryKeys())
        accepts(ProfileRepository(store: store))
        accepts(ConversationRepository(store: store))
        accepts(GoalRepository(store: store))
        accepts(ActionRepository(store: store))
        accepts(EvidenceRepository(store: store))
        accepts(MemoryRepository(store: store))
        acceptsMessages(ConversationRepository(store: store))
        acceptsMilestones(GoalRepository(store: store))
        acceptsSources(MemoryRepository(store: store))
    }

    @Test(arguments: RepositoryCase.allCases)
    func createUpdateDeleteIdempotencyIsolationAndRollback(kind: RepositoryCase) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: RepositoryKeys())
        let id = UUID().uuidString
        let parent = UUID().uuidString
        let context = MutationContext(id: UUID().uuidString, deviceID: UUID().uuidString, timestamp: 100)
        switch kind {
        case .profile:
            try await exercise(ProfileRepository(store: store), store: store, original: ProfileRecord(id: id, displayName: "One", headline: "Designer", biography: "PRIVATE-CANARY", updatedAtMS: 100), updated: ProfileRecord(id: id, displayName: "Two", headline: "Designer", biography: "PRIVATE-CANARY", updatedAtMS: 101), context: context)
        case .conversation:
            try await exercise(ConversationRepository(store: store), store: store, original: ConversationRecord(id: id, title: "One", createdAtMS: 100, updatedAtMS: 100), updated: ConversationRecord(id: id, title: "Two", createdAtMS: 100, updatedAtMS: 101), context: context)
        case .message:
            try await store.write { db in try db.execute(sql: "INSERT INTO conversations (id, title, created_at_ms, updated_at_ms) VALUES (?, '', 100, 100)", arguments: [parent]) }
            try await exercise(MessageAdapter(repository: ConversationRepository(store: store)), store: store, original: MessageRecord(id: id, conversationID: parent, role: "user", body: "One", createdAtMS: 100), updated: MessageRecord(id: id, conversationID: parent, role: "user", body: "Two", createdAtMS: 100), context: context, appendOnly: true)
        case .goal:
            try await exercise(GoalRepository(store: store), store: store, original: GoalRecord(id: id, title: "One", detail: "", status: "active", createdAtMS: 100, updatedAtMS: 100), updated: GoalRecord(id: id, title: "Two", detail: "", status: "active", createdAtMS: 100, updatedAtMS: 101), context: context)
        case .milestone:
            try await store.write { db in try db.execute(sql: "INSERT INTO goals (id, title, status, created_at_ms, updated_at_ms) VALUES (?, 'parent', 'active', 100, 100)", arguments: [parent]) }
            try await exercise(MilestoneAdapter(repository: GoalRepository(store: store)), store: store, original: MilestoneRecord(id: id, goalID: parent, title: "One", status: "open", targetAtMS: nil, updatedAtMS: 100), updated: MilestoneRecord(id: id, goalID: parent, title: "Two", status: "open", targetAtMS: nil, updatedAtMS: 101), context: context)
        case .action:
            try await exercise(ActionRepository(store: store), store: store, original: ActionRecord(id: id, goalID: nil, title: "One", detail: "", status: "open", dueAtMS: nil, createdAtMS: 100, updatedAtMS: 100), updated: ActionRecord(id: id, goalID: nil, title: "Two", detail: "", status: "open", dueAtMS: nil, createdAtMS: 100, updatedAtMS: 101), context: context)
        case .evidence:
            try await exercise(EvidenceRepository(store: store), store: store, original: EvidenceRecord(id: id, goalID: nil, actionID: nil, title: "One", detail: "", occurredAtMS: 100, createdAtMS: 100), updated: EvidenceRecord(id: id, goalID: nil, actionID: nil, title: "Two", detail: "", occurredAtMS: 100, createdAtMS: 100), context: context)
        case .memory:
            try await exercise(MemoryRepository(store: store), store: store, original: MemoryRecord(id: id, kind: "fact", content: "One", status: "active", createdAtMS: 100, updatedAtMS: 100), updated: MemoryRecord(id: id, kind: "fact", content: "Two", status: "active", createdAtMS: 100, updatedAtMS: 101), context: context)
        case .source:
            try await store.write { db in try db.execute(sql: "INSERT INTO memory_items (id, kind, content, status, created_at_ms, updated_at_ms) VALUES (?, 'fact', 'parent', 'active', 100, 100)", arguments: [parent]) }
            let sourceID = UUID().uuidString
            try await exercise(SourceAdapter(repository: MemoryRepository(store: store)), store: store, original: MemorySourceRecord(id: id, memoryItemID: parent, sourceType: "evidence", sourceID: sourceID, createdAtMS: 100), updated: MemorySourceRecord(id: id, memoryItemID: parent, sourceType: "conversation", sourceID: sourceID, createdAtMS: 100), context: context)
        }
    }

    private func exercise<R: ContractRepository>(_ repository: R, store: TaisaStore, original: R.Record, updated: R.Record, context: MutationContext, appendOnly: Bool = false) async throws {
        let journal = ChangeJournal(store: store)
        let baseline = try await journal.pending(limit: 200).count
        // The journal failure must roll back both the domain row and field ancestry.
        try await store.write { db in try db.execute(sql: "CREATE TRIGGER fail_outbox BEFORE INSERT ON outbox BEGIN SELECT RAISE(ABORT, 'forced'); END") }
        await #expect(throws: Error.self) { try await repository.create(original, context: context) }
        #expect(try await repository.get(id: original.id) == nil)
        try await store.write { db in try db.execute(sql: "DROP TRIGGER fail_outbox") }
        try await repository.create(original, context: context)
        try await repository.create(original, context: context)
        #expect(try await repository.get(id: original.id) == original)
        #expect(try await journal.pending(limit: 200).count == baseline + 1)
        let isolatedDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: isolatedDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: isolatedDirectory) }
        let isolatedStore = try await TaisaStore.open(at: isolatedDirectory.appendingPathComponent("store.sqlite"), keyStore: RepositoryKeys())
        #expect(try await R(store: isolatedStore).get(id: original.id) == nil)
        #expect(try await ChangeJournal(store: isolatedStore).pending(limit: 10).isEmpty)
        #expect(try await repository.get(id: UUID().uuidString) == nil)
        let second = MutationContext(id: UUID().uuidString, deviceID: context.deviceID, timestamp: 101)
        if !appendOnly {
            try await repository.update(updated, context: second)
            #expect(try await repository.get(id: original.id) == updated)
            #expect(try await journal.pending(limit: 200).count == baseline + 2)
        }
        try await repository.delete(id: original.id, context: MutationContext(id: UUID().uuidString, deviceID: context.deviceID, timestamp: 102))
        #expect(try await repository.get(id: original.id) == nil)
        #expect(try await journal.pending(limit: 200).count == baseline + (appendOnly ? 2 : 3))
    }

    @Test func productionMessageCreateRejectsDifferentContentForExistingID() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: RepositoryKeys())
        let repository = ConversationRepository(store: store)
        let conversationID = UUID().uuidString, messageID = UUID().uuidString, deviceID = UUID().uuidString
        try await repository.create(
            ConversationRecord(id: conversationID, title: "Conversation", createdAtMS: 100, updatedAtMS: 100),
            context: MutationContext(id: UUID().uuidString, deviceID: deviceID, timestamp: 100)
        )
        let original = MessageRecord(id: messageID, conversationID: conversationID, role: "user", body: "Original", createdAtMS: 101)
        let changed = MessageRecord(id: messageID, conversationID: conversationID, role: "user", body: "Changed", createdAtMS: 101)
        try await repository.createMessage(original, context: MutationContext(id: UUID().uuidString, deviceID: deviceID, timestamp: 101))
        let before = try await ChangeJournal(store: store).pending(limit: 10)
        let versionsBefore = try await store.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM field_versions WHERE entity_type = 'message' AND entity_id = ?", arguments: [messageID]) }
        await #expect(throws: RepositoryError.alreadyExists) {
            try await repository.createMessage(changed, context: MutationContext(id: UUID().uuidString, deviceID: deviceID, timestamp: 102))
        }
        #expect(try await repository.message(id: messageID) == original)
        #expect(try await ChangeJournal(store: store).pending(limit: 10) == before)
        #expect(try await store.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM field_versions WHERE entity_type = 'message' AND entity_id = ?", arguments: [messageID]) } == versionsBefore)
    }

    @Test func profileUpdateDeleteReplayAndFailureRollbackPreserveCausality() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: RepositoryKeys())
        let repository = ProfileRepository(store: store), journal = ChangeJournal(store: store)
        let id = UUID().uuidString, deviceID = UUID().uuidString
        let original = ProfileRecord(id: id, displayName: "First", headline: "", biography: "", updatedAtMS: 100)
        let updated = ProfileRecord(id: id, displayName: "Second", headline: "", biography: "", updatedAtMS: 101)
        let create = MutationContext(id: UUID().uuidString, deviceID: deviceID, timestamp: 100)
        let update = MutationContext(id: UUID().uuidString, deviceID: deviceID, timestamp: 101)
        let delete = MutationContext(id: UUID().uuidString, deviceID: deviceID, timestamp: 102)
        try await repository.create(original, context: create)
        func counts() async throws -> (Int, Int, Int) {
            try await store.read { db in
                (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM field_versions") ?? -1,
                 try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tombstones") ?? -1,
                 try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM outbox") ?? -1)
            }
        }
        let baseline = try await counts()
        try await store.write { db in try db.execute(sql: "CREATE TRIGGER fail_outbox BEFORE INSERT ON outbox BEGIN SELECT RAISE(ABORT, 'PRIVATE-ROLLBACK-CANARY'); END") }
        await #expect(throws: RepositoryError.persistenceFailed) { try await repository.update(updated, context: update) }
        #expect(try await repository.get(id: id) == original)
        #expect(try await counts() == baseline)
        try await store.write { db in try db.execute(sql: "DROP TRIGGER fail_outbox") }
        try await repository.update(updated, context: update)
        try await repository.update(updated, context: update)
        #expect(try await repository.get(id: id) == updated)
        let afterUpdate = try await counts()
        #expect(afterUpdate.0 == baseline.0 + 3)
        #expect(afterUpdate.2 == baseline.2 + 1)
        let last = try #require(await journal.pending(limit: 10).last)
        #expect(last.causality.changedFields.first { $0.fieldName == "displayName" }?.parentVersionID == create.id)
        try await store.write { db in try db.execute(sql: "CREATE TRIGGER fail_outbox BEFORE INSERT ON outbox BEGIN SELECT RAISE(ABORT, 'PRIVATE-ROLLBACK-CANARY'); END") }
        await #expect(throws: RepositoryError.persistenceFailed) { try await repository.delete(id: id, context: delete) }
        #expect(try await repository.get(id: id) == updated)
        #expect(try await counts() == afterUpdate)
        try await store.write { db in try db.execute(sql: "DROP TRIGGER fail_outbox") }
        try await repository.delete(id: id, context: delete)
        try await repository.delete(id: id, context: delete)
        #expect(try await repository.get(id: id) == nil)
        let afterDelete = try await counts()
        #expect(afterDelete.0 == afterUpdate.0 + 1)
        #expect(afterDelete.1 == 1)
        #expect(afterDelete.2 == afterUpdate.2 + 1)
    }

    @Test func reusedMutationIDCannotCreateDifferentProfile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: RepositoryKeys())
        let repository = ProfileRepository(store: store)
        let context = MutationContext(id: UUID().uuidString, deviceID: UUID().uuidString, timestamp: 100)
        let first = ProfileRecord(id: UUID().uuidString, displayName: "First", headline: "", biography: "", updatedAtMS: 100)
        let second = ProfileRecord(id: UUID().uuidString, displayName: "Second", headline: "", biography: "", updatedAtMS: 100)
        try await repository.create(first, context: context)
        await #expect(throws: RepositoryError.mutationCollision) { try await repository.create(second, context: context) }
        #expect(try await repository.get(id: second.id) == nil)
    }

    @Test func reusedMutationIDCannotChangePayloadOrOperation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: RepositoryKeys())
        let repository = ProfileRepository(store: store)
        let context = MutationContext(id: UUID().uuidString, deviceID: UUID().uuidString, timestamp: 100)
        let original = ProfileRecord(id: UUID().uuidString, displayName: "First", headline: "", biography: "", updatedAtMS: 100)
        let changed = ProfileRecord(id: original.id, displayName: "Different", headline: "", biography: "", updatedAtMS: 100)
        try await repository.create(original, context: context)
        await #expect(throws: RepositoryError.mutationCollision) { try await repository.create(changed, context: context) }
        await #expect(throws: RepositoryError.mutationCollision) { try await repository.delete(id: original.id, context: context) }
        #expect(try await repository.get(id: original.id) == original)
    }

    @Test func rejectedRecordErrorDoesNotRevealPrivateContent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: RepositoryKeys())
        let record = GoalRecord(id: UUID().uuidString, title: "PRIVATE-ERROR-CANARY", detail: "", status: "invalid", createdAtMS: 100, updatedAtMS: 100)
        let context = MutationContext(id: UUID().uuidString, deviceID: UUID().uuidString, timestamp: 100)
        do {
            try await GoalRepository(store: store).create(record, context: context)
            Issue.record("Invalid status was accepted")
        } catch {
            #expect(!String(describing: error).contains("PRIVATE-ERROR-CANARY"))
            #expect(error is RepositoryError)
        }
    }
}
