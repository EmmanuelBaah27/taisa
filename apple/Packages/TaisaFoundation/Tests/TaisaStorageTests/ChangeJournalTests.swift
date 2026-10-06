import Foundation
import Testing
@testable import TaisaStorage

private actor JournalKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}

@Suite(.serialized) struct ChangeJournalTests {
    @Test func pendingIsBoundedFIFOAndAcknowledgementIsIdempotent() async throws {
        let (store, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ProfileRepository(store: store)
        let journal = ChangeJournal(store: store)
        let device = UUID().uuidString
        let first = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 100)
        let second = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 101)
        let id = UUID().uuidString
        try await repository.create(ProfileRecord(id: id, displayName: "One", headline: "", biography: "", updatedAtMS: 100), context: first)
        try await repository.update(ProfileRecord(id: id, displayName: "Two", headline: "", biography: "", updatedAtMS: 101), context: second)
        #expect(try await journal.pending(limit: 1).map(\.id) == [first.id])
        #expect(try await journal.pending(limit: 200).map(\.id) == [first.id, second.id])
        #expect(try await journal.pending(limit: 0).isEmpty)
        try await journal.retry(id: first.id, category: "offline")
        #expect(try await journal.pending(limit: 1).first?.retryCategory == "offline")
        #expect(try await journal.pending(limit: 1).first?.attempts == 1)
        try await journal.acknowledge(id: first.id, at: 102)
        try await journal.acknowledge(id: first.id, at: 103)
        #expect(try await journal.pending(limit: 10).map(\.id) == [second.id])
    }

    @Test func pendingPreservesCommitOrderWhenDeviceClockMovesBackward() async throws {
        let (store, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ProfileRepository(store: store)
        let device = UUID().uuidString
        let first = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 200)
        let second = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 100)
        try await repository.create(ProfileRecord(id: UUID().uuidString, displayName: "First", headline: "", biography: "", updatedAtMS: 200), context: first)
        try await repository.create(ProfileRecord(id: UUID().uuidString, displayName: "Second", headline: "", biography: "", updatedAtMS: 100), context: second)
        #expect(try await ChangeJournal(store: store).pending(limit: 10).map(\.id) == [first.id, second.id])
    }

    @Test func supersessionRequiresCompleteDirectFieldAncestryAndUnsentUpdate() async throws {
        let (store, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ProfileRepository(store: store)
        let journal = ChangeJournal(store: store)
        let id = UUID().uuidString
        let device = UUID().uuidString
        let create = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 100)
        let first = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 101)
        let second = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 102)
        try await repository.create(ProfileRecord(id: id, displayName: "One", headline: "H1", biography: "", updatedAtMS: 100), context: create)
        try await repository.update(ProfileRecord(id: id, displayName: "Two", headline: "H2", biography: "", updatedAtMS: 101), context: first)
        try await repository.update(ProfileRecord(id: id, displayName: "Three", headline: "H2", biography: "", updatedAtMS: 102), context: second)
        #expect(try await journal.supersede(olderID: create.id, by: first.id, at: 103) == false)
        #expect(try await journal.supersede(olderID: first.id, by: second.id, at: 103) == false)
        #expect(try await journal.pending(limit: 10).count == 3)
    }

    @Test func adjacentUpdateSupersedesWhenAllChangedFieldsDescend() async throws {
        let (store, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ProfileRepository(store: store)
        let journal = ChangeJournal(store: store)
        let id = UUID().uuidString
        let device = UUID().uuidString
        let create = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 100)
        let first = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 101)
        let second = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 102)
        try await repository.create(ProfileRecord(id: id, displayName: "One", headline: "", biography: "", updatedAtMS: 100), context: create)
        try await repository.update(ProfileRecord(id: id, displayName: "Two", headline: "", biography: "", updatedAtMS: 101), context: first)
        try await repository.update(ProfileRecord(id: id, displayName: "Three", headline: "", biography: "", updatedAtMS: 102), context: second)
        #expect(try await journal.supersede(olderID: first.id, by: second.id, at: 103))
        #expect(try await journal.pending(limit: 10).map(\.id) == [create.id, second.id])
    }

    @Test func canonicalMutationHasStableContentOnlyEncoding() async throws {
        let (store, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = "00000000-0000-4000-8000-000000000001"
        let mutationID = "00000000-0000-4000-8000-000000000002"
        let deviceID = "00000000-0000-4000-8000-000000000003"
        let record = ProfileRecord(id: id, displayName: "Name", headline: "Designer", biography: "Bio", updatedAtMS: 100)
        try await ProfileRepository(store: store).create(record, context: MutationContext(id: mutationID, deviceID: deviceID, timestamp: 100))
        let payload = try #require(await ChangeJournal(store: store).pending(limit: 1).first?.payload)
        let fieldNames = ["biography", "displayName", "headline", "updatedAtMS"]
        let changedFields = fieldNames.map { name in
            "{\"ancestorVersionIDs\":[],\"deviceCounter\":1,\"fieldName\":\"\(name)\",\"versionID\":\"\(mutationID)\"}"
        }.joined(separator: ",")
        let causality = "{\"changedFields\":[\(changedFields)],\"deviceCounter\":1,\"deviceID\":\"\(deviceID)\",\"logicalVersionID\":\"\(mutationID)\",\"observedFieldVersions\":[]}"
        let expected = "{\"causality\":\(causality),\"deviceID\":\"\(deviceID)\",\"entityID\":\"\(id)\",\"entityType\":\"profile\",\"id\":\"\(mutationID)\",\"operation\":\"create\",\"record\":{\"biography\":\"Bio\",\"displayName\":\"Name\",\"headline\":\"Designer\",\"id\":\"\(id)\",\"updatedAtMS\":100},\"timestamp\":100}"
        #expect(payload == Data(expected.utf8))
        #expect(!payload.contains(Data("audioURI".utf8)))
        #expect(!payload.contains(Data("recoveryKey".utf8)))
    }

    private func fixture() async throws -> (TaisaStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: JournalKeys())
        return (store, directory)
    }
}
