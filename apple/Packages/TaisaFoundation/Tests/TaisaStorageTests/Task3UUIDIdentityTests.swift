import Foundation
import GRDB
import Testing
@testable import TaisaStorage

private actor UUIDIdentityKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}

@Suite(.serialized) struct Task3UUIDIdentityTests {
    private func fixture() async throws -> (TaisaStore, URL, UUIDIdentityKeys) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let keys = UUIDIdentityKeys()
        return (try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: keys), directory, keys)
    }

    @Test func casingVariantsOfOneMutationReplayOnceWithCanonicalPublicIDs() async throws {
        let (store, directory, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ProfileRepository(store: store), journal = ChangeJournal(store: store)
        let entityLower = "abcdefab-1234-4567-89ab-abcdefabcdef"
        let entityUpper = "ABCDEFAB-1234-4567-89AB-ABCDEFABCDEF"
        let mutationLower = "abcdefab-1234-4567-89ab-abcdefabcdea"
        let mutationUpper = "ABCDEFAB-1234-4567-89AB-ABCDEFABCDEA"
        let deviceMixed = "aBcDeFaB-1234-4567-89aB-AbCdEfAbCdEb"
        let deviceUpper = "ABCDEFAB-1234-4567-89AB-ABCDEFABCDEB"
        let lower = ProfileRecord(id: entityLower, displayName: "First", headline: "", biography: "", updatedAtMS: 100)
        let upper = ProfileRecord(id: entityUpper, displayName: "First", headline: "", biography: "", updatedAtMS: 100)
        try await repository.create(lower, context: MutationContext(id: mutationLower, deviceID: deviceMixed, timestamp: 100))
        try await repository.create(upper, context: MutationContext(id: mutationUpper, deviceID: deviceUpper, timestamp: 100))
        #expect(try await repository.get(id: entityLower) == upper)
        #expect(try await repository.get(id: entityUpper) == upper)
        let pending = try await journal.pending(limit: 10)
        #expect(pending.count == 1)
        #expect(pending.first?.id == mutationUpper)
        #expect(pending.first?.entityID == entityUpper)
        #expect(pending.first?.causality.logicalVersionID == mutationUpper)
        #expect(pending.first?.causality.deviceID == deviceUpper)
        await #expect(throws: RepositoryError.mutationCollision) {
            try await repository.create(ProfileRecord(id: entityLower, displayName: "Different", headline: "", biography: "", updatedAtMS: 100), context: MutationContext(id: mutationLower, deviceID: deviceMixed, timestamp: 100))
        }
        #expect(try await journal.pending(limit: 10).count == 1)
    }

    @Test func mixedCaseReplacementChainRemainsReadableAndAcknowledgableAfterRelaunch() async throws {
        let (store, directory, keys) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ProfileRepository(store: store), journal = ChangeJournal(store: store)
        let entity = "abcdefab-1234-4567-89ab-abcdefabcdf0"
        let device = "abcdefab-1234-4567-89ab-abcdefabcdf1"
        let create = "abcdefab-1234-4567-89ab-abcdefabcdf2"
        let older = "abcdefab-1234-4567-89ab-abcdefabcdf3"
        let middle = "aBcDeFaB-1234-4567-89aB-AbCdEfAbCdF4"
        let newer = "abcdefab-1234-4567-89ab-abcdefabcdf5"
        for (mutation, name, timestamp) in [(create, "A", Int64(100)), (older, "B", 101), (middle, "C", 102), (newer, "D", 103)] {
            let record = ProfileRecord(id: entity, displayName: name, headline: "", biography: "", updatedAtMS: timestamp)
            let context = MutationContext(id: mutation, deviceID: device, timestamp: timestamp)
            if mutation == create { try await repository.create(record, context: context) }
            else { try await repository.update(record, context: context) }
        }
        #expect(try await journal.supersede(olderID: older, by: middle, at: 104))
        #expect(try await journal.supersede(olderID: middle, by: newer.uppercased(), at: 105))
        let middleUpper = middle.uppercased(), newerUpper = newer.uppercased(), olderUpper = older.uppercased()
        #expect(try await journal.state(id: olderUpper) == .superseded(by: middleUpper, remotelyAcknowledgedAtMS: nil))
        // Preserve a pre-policy spelling on disk; reads must follow the same
        // semantic replacement chain without rewriting its acknowledged row.
        try await store.write { db in
            try db.execute(sql: "UPDATE outbox SET retry_category = ? WHERE mutation_id = ?", arguments: ["superseded:\(middle.lowercased())", olderUpper])
        }
        let reopened = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: keys)
        let resumed = ChangeJournal(store: reopened)
        #expect(try await resumed.remoteCoverage(id: older) == .waitingFor(newerUpper))
        try await resumed.retry(id: older, category: "offline")
        try await resumed.acknowledge(id: middle, at: 106)
        #expect(try await resumed.state(id: middleUpper) == .superseded(by: newerUpper, remotelyAcknowledgedAtMS: 106))
        #expect(try await resumed.remoteCoverage(id: older) == .confirmed)
        try await resumed.acknowledge(id: newer, at: 107)
        #expect(try await resumed.remoteCoverage(id: olderUpper) == .confirmed)
    }

    @Test func malformedIdentifiersFailWithoutEchoingInput() async throws {
        let (store, directory, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ProfileRepository(store: store)
        let malformed = "PRIVATE-ID-CANARY-NOT-A-UUID"
        for operation in ["entity", "mutation", "device"] {
            do {
                let entityID = operation == "entity" ? malformed : UUID().uuidString
                let mutationID = operation == "mutation" ? malformed : UUID().uuidString
                let deviceID = operation == "device" ? malformed : UUID().uuidString
                try await repository.create(ProfileRecord(id: entityID, displayName: "Name", headline: "", biography: "", updatedAtMS: 100), context: MutationContext(id: mutationID, deviceID: deviceID, timestamp: 100))
                Issue.record("Malformed \(operation) ID was accepted")
            } catch {
                #expect(error as? RepositoryError == .invalidIdentifier)
                #expect(!String(describing: error).contains(malformed))
            }
        }
    }

    @Test func previouslyPersistedLowercaseMutationReplaysWithoutForking() async throws {
        let (store, directory, keys) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let entity = "ABCDEFAB-1234-4567-89AB-ABCDEFABCDF6"
        let mutation = "ABCDEFAB-1234-4567-89AB-ABCDEFABCDF7"
        let device = "ABCDEFAB-1234-4567-89AB-ABCDEFABCDF8"
        let privateText = "abcdefab-1234-4567-89ab-abcdefabcdf0"
        let record = ProfileRecord(id: entity, displayName: privateText, headline: "", biography: "", updatedAtMS: 100)
        let context = MutationContext(id: mutation, deviceID: device, timestamp: 100)
        try await ProfileRepository(store: store).create(record, context: context)
        let originalPayload = try #require(await ChangeJournal(store: store).pending(limit: 1).first?.payload)
        var legacyPayload = try #require(String(data: originalPayload, encoding: .utf8))
        for identifier in [entity, mutation, device] { legacyPayload = legacyPayload.replacingOccurrences(of: identifier, with: identifier.lowercased()) }
        let legacyBytes = Data(legacyPayload.utf8)
        try await store.write { db in
            try db.execute(sql: "UPDATE profile SET id = ? WHERE id = ?", arguments: [entity.lowercased(), entity])
            try db.execute(sql: "UPDATE field_versions SET entity_id = ?, version_id = ?, device_id = ? WHERE entity_id = ?", arguments: [entity.lowercased(), mutation.lowercased(), device.lowercased(), entity])
            try db.execute(sql: "UPDATE outbox SET mutation_id = ?, entity_id = ?, payload = ? WHERE mutation_id = ?", arguments: [mutation.lowercased(), entity.lowercased(), legacyBytes, mutation])
        }
        let reopened = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: keys)
        let repository = ProfileRepository(store: reopened), journal = ChangeJournal(store: reopened)
        #expect(try await repository.get(id: entity) == record)
        let pending = try #require(await journal.pending(limit: 1).first)
        #expect(pending.id == mutation)
        #expect(pending.causality.deviceID == device)
        let publicPayload = try #require(String(data: pending.payload, encoding: .utf8))
        #expect(publicPayload.contains("\"entityID\":\"\(entity)\""))
        #expect(publicPayload.contains("\"deviceID\":\"\(device)\""))
        #expect(publicPayload.contains("\"displayName\":\"\(privateText)\""))
        try await repository.create(record, context: context)
        #expect(try await journal.pending(limit: 10).count == 1)
        #expect(try await repository.get(id: entity.lowercased()) == record)
    }

    @Test func preexistingCaseVariantForkFailsClosedInsteadOfChoosingArbitraryRow() async throws {
        let (store, directory, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let entity = "ABCDEFAB-1234-4567-89AB-ABCDEFABCDF9"
        let mutation = "ABCDEFAB-1234-4567-89AB-ABCDEFABCDFA"
        let context = MutationContext(id: mutation, deviceID: UUID().uuidString, timestamp: 100)
        try await ProfileRepository(store: store).create(ProfileRecord(id: entity, displayName: "First", headline: "", biography: "", updatedAtMS: 100), context: context)
        try await store.write { db in
            try db.execute(sql: "INSERT INTO profile (id, display_name, headline, biography, updated_at_ms) VALUES (?, 'Fork', '', '', 100)", arguments: [entity.lowercased()])
            try db.execute(sql: "INSERT INTO outbox (id, mutation_id, entity_type, entity_id, payload, status, created_at_ms) SELECT ?, ?, entity_type, entity_id, payload, status, created_at_ms FROM outbox WHERE mutation_id = ?", arguments: [UUID().uuidString, mutation.lowercased(), mutation])
        }
        await #expect(throws: RepositoryError.persistenceFailed) { _ = try await ProfileRepository(store: store).get(id: entity) }
        await #expect(throws: RepositoryError.persistenceFailed) { _ = try await ChangeJournal(store: store).state(id: mutation) }
        await #expect(throws: RepositoryError.persistenceFailed) { _ = try await ChangeJournal(store: store).pending(limit: 10) }
    }

    @Test func reservationTokenIdentityIsCaseInsensitiveAndPubliclyCanonical() async throws {
        let (store, directory, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mutation = "ABCDEFAB-1234-4567-89AB-ABCDEFABCDFB"
        try await ProfileRepository(store: store).create(ProfileRecord(id: UUID().uuidString, displayName: "Name", headline: "", biography: "", updatedAtMS: 100), context: MutationContext(id: mutation, deviceID: UUID().uuidString, timestamp: 100))
        let token = "ABCDEFAB-1234-4567-89AB-ABCDEFABCDFC"
        let marker = "reserved:00000000000000000210:\(token.lowercased())"
        try await store.write { db in try db.execute(sql: "UPDATE outbox SET status = 'retrying', retry_category = ? WHERE mutation_id = ?", arguments: [marker, mutation]) }
        let journal = ChangeJournal(store: store)
        #expect(try await journal.state(id: mutation.lowercased()) == .reserved(reservationID: token, expiresAtMS: 210, attempts: 0))
        #expect(try await journal.reservePending(limit: 1, at: 209, leaseDurationMS: 10).isEmpty)
        try await journal.retry(id: mutation.lowercased(), category: "offline", reservationID: token)
        #expect(try await journal.pending(limit: 1).first?.retryCategory == "offline")
        let reserved = try #require(await journal.reservePending(limit: 1, at: 211, leaseDurationMS: 10).first)
        try await journal.retry(id: mutation, category: "transport", reservationID: reserved.reservationID.lowercased())
        #expect(try await journal.state(id: mutation) == .retrying(category: "transport", attempts: 2))
        await #expect(throws: RepositoryError.invalidIdentifier) { try await journal.retry(id: mutation, category: "offline", reservationID: "PRIVATE-TOKEN-CANARY") }
    }

    @Test func childWriteUsesLegacyLowercaseParentWithoutChangingPublicIdentity() async throws {
        let (store, directory, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let conversation = "ABCDEFAB-1234-4567-89AB-ABCDEFABCDFD"
        let message = "ABCDEFAB-1234-4567-89AB-ABCDEFABCDFE"
        let repository = ConversationRepository(store: store)
        try await repository.create(ConversationRecord(id: conversation, title: "Legacy", createdAtMS: 100, updatedAtMS: 100), context: MutationContext(id: UUID().uuidString, deviceID: UUID().uuidString, timestamp: 100))
        try await store.write { db in try db.execute(sql: "UPDATE conversations SET id = ? WHERE id = ?", arguments: [conversation.lowercased(), conversation]) }
        let record = MessageRecord(id: message.lowercased(), conversationID: conversation.lowercased(), role: "user", body: "Hello", createdAtMS: 101)
        try await repository.createMessage(record, context: MutationContext(id: UUID().uuidString, deviceID: UUID().uuidString, timestamp: 101))
        #expect(try await repository.message(id: message.lowercased())?.conversationID == conversation)
        #expect(try await ChangeJournal(store: store).pending(limit: 10).last?.entityID == message)
    }
}
