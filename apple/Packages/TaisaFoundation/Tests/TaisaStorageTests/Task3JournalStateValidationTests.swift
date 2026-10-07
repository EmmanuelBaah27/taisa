import Foundation
import GRDB
import Testing
@testable import TaisaStorage

private actor StateValidationKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}

@Suite(.serialized) struct Task3JournalStateValidationTests {
    private func fixture() async throws -> (TaisaStore, URL, String) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: StateValidationKeys())
        let mutationID = UUID().uuidString
        try await ProfileRepository(store: store).create(
            ProfileRecord(id: UUID().uuidString, displayName: "Name", headline: "", biography: "", updatedAtMS: 100),
            context: MutationContext(id: mutationID, deviceID: UUID().uuidString, timestamp: 100)
        )
        return (store, directory, mutationID)
    }

    @Test func malformedUploadStatesFailClosedAcrossPublicPaths() async throws {
        let token = UUID().uuidString
        let cases: [(String, String, String?)] = [
            ("broken lease", "retrying", "reserved:not-a-lease"),
            ("unknown retry", "retrying", "PRIVATE-RETRY-CANARY"),
            ("negative lease", "retrying", "reserved:-0000000000000000001:\(token)"),
            ("overflow lease", "retrying", "reserved:99999999999999999999:\(token)"),
            ("invalid lease token", "retrying", "reserved:00000000000000000200:not-a-uuid"),
            ("contradictory pending", "pending", "offline")
        ]
        for (label, status, category) in cases {
            for operation in ["pending", "reserve", "state", "ack", "retry", "coverage"] {
                let (store, directory, mutationID) = try await fixture()
                defer { try? FileManager.default.removeItem(at: directory) }
                try await store.write { db in
                    try db.execute(sql: "UPDATE outbox SET status = ?, retry_category = ? WHERE mutation_id = ?", arguments: [status, category, mutationID])
                }
                let journal = ChangeJournal(store: store)
                await #expect(throws: RepositoryError.persistenceFailed, "\(label): \(operation)") {
                    switch operation {
                    case "pending": _ = try await journal.pending(limit: 1)
                    case "reserve": _ = try await journal.reservePending(limit: 1, at: 200, leaseDurationMS: 10)
                    case "state": _ = try await journal.state(id: mutationID)
                    case "ack": try await journal.acknowledge(id: mutationID, at: 201)
                    case "retry": try await journal.retry(id: mutationID, category: "offline")
                    default: _ = try await journal.remoteCoverage(id: mutationID)
                    }
                }
                let stored: String? = try await store.read { db in try String.fetchOne(db, sql: "SELECT retry_category FROM outbox WHERE mutation_id = ?", arguments: [mutationID]) }
                #expect(stored == category, "\(label): \(operation) preserved state")
            }
        }
    }

    @Test func malformedSupersessionCandidateAndReplacementMarkerFailClosed() async throws {
        let (store, directory, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ProfileRepository(store: store), journal = ChangeJournal(store: store)
        let id = UUID().uuidString, deviceID = UUID().uuidString
        let create = MutationContext(id: UUID().uuidString, deviceID: deviceID, timestamp: 100)
        let older = MutationContext(id: UUID().uuidString, deviceID: deviceID, timestamp: 101)
        let newer = MutationContext(id: UUID().uuidString, deviceID: deviceID, timestamp: 102)
        try await repository.create(ProfileRecord(id: id, displayName: "a", headline: "", biography: "", updatedAtMS: 100), context: create)
        try await repository.update(ProfileRecord(id: id, displayName: "b", headline: "", biography: "", updatedAtMS: 101), context: older)
        try await repository.update(ProfileRecord(id: id, displayName: "c", headline: "", biography: "", updatedAtMS: 102), context: newer)
        for candidate in [older.id, newer.id] {
            try await store.write { db in try db.execute(sql: "UPDATE outbox SET retry_category = 'offline' WHERE mutation_id = ?", arguments: [candidate]) }
            await #expect(throws: RepositoryError.persistenceFailed) { _ = try await journal.supersede(olderID: older.id, by: newer.id, at: 103) }
            try await store.write { db in try db.execute(sql: "UPDATE outbox SET status = 'pending', retry_category = NULL, acknowledged_at_ms = NULL WHERE mutation_id IN (?, ?)", arguments: [older.id, newer.id]) }
        }
        try await store.write { db in try db.execute(sql: "UPDATE outbox SET status = 'acknowledged', retry_category = 'superseded:not-a-uuid' WHERE mutation_id = ?", arguments: [older.id]) }
        await #expect(throws: RepositoryError.persistenceFailed) { _ = try await journal.state(id: older.id) }
        await #expect(throws: RepositoryError.persistenceFailed) { _ = try await journal.acknowledge(id: older.id, at: 104) }
        await #expect(throws: RepositoryError.persistenceFailed) { try await journal.retry(id: older.id, category: "offline") }
        await #expect(throws: RepositoryError.persistenceFailed) { _ = try await journal.remoteCoverage(id: older.id) }
        await #expect(throws: RepositoryError.persistenceFailed) { _ = try await journal.supersede(olderID: older.id, by: newer.id, at: 104) }
    }

    @Test func laterMalformedBatchCandidateRollsBackEarlierReservation() async throws {
        let (store, directory, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let second = MutationContext(id: UUID().uuidString, deviceID: UUID().uuidString, timestamp: 101)
        try await ProfileRepository(store: store).create(ProfileRecord(id: UUID().uuidString, displayName: "Second", headline: "", biography: "", updatedAtMS: 101), context: second)
        try await store.write { db in try db.execute(sql: "UPDATE outbox SET status = 'retrying', retry_category = 'PRIVATE-RETRY-CANARY' WHERE mutation_id = ?", arguments: [second.id]) }
        let journal = ChangeJournal(store: store)
        await #expect(throws: RepositoryError.persistenceFailed) { _ = try await journal.reservePending(limit: 2, at: 200, leaseDurationMS: 10) }
        let firstState = try await store.read { db in try String.fetchOne(db, sql: "SELECT status FROM outbox ORDER BY rowid LIMIT 1") }
        #expect(firstState == "pending")
    }

    @Test func expiryReclaimKeepsInternalMarkersOutOfPublicRetryCategory() async throws {
        let (store, directory, mutationID) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = ChangeJournal(store: store)
        let first = try #require(await journal.reservePending(limit: 1, at: 200, leaseDurationMS: 10).first)
        #expect(first.change.retryCategory == nil)
        #expect(try await journal.reservePending(limit: 1, at: 0, leaseDurationMS: 10).isEmpty)
        let second = try #require(await journal.reservePending(limit: 1, at: 210, leaseDurationMS: 10).first)
        #expect(second.change.retryCategory == nil)
        #expect(second.reservationID != first.reservationID)
        await #expect(throws: RepositoryError.reservationMismatch) { try await journal.retry(id: mutationID, category: "offline", reservationID: first.reservationID) }
        #expect(try await journal.state(id: mutationID) == .reserved(reservationID: second.reservationID, expiresAtMS: 220, attempts: 0))
        try await journal.acknowledge(id: mutationID, at: 0)
        #expect(try await journal.state(id: mutationID) == .remotelyAcknowledged(atMS: 100))
    }

    @Test func malformedLeaseRemainsRejectedAfterRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite"), keys = StateValidationKeys()
        let original = try await TaisaStore.open(at: url, keyStore: keys)
        let mutationID = UUID().uuidString
        try await ProfileRepository(store: original).create(ProfileRecord(id: UUID().uuidString, displayName: "Name", headline: "", biography: "", updatedAtMS: 100), context: MutationContext(id: mutationID, deviceID: UUID().uuidString, timestamp: 100))
        let invalid = "reserved:99999999999999999999:\(UUID().uuidString)"
        try await original.write { db in try db.execute(sql: "UPDATE outbox SET status = 'retrying', retry_category = ? WHERE mutation_id = ?", arguments: [invalid, mutationID]) }
        let reopened = try await TaisaStore.open(at: url, keyStore: keys)
        let journal = ChangeJournal(store: reopened)
        await #expect(throws: RepositoryError.persistenceFailed) { _ = try await journal.pending(limit: 1) }
        await #expect(throws: RepositoryError.persistenceFailed) { _ = try await journal.reservePending(limit: 1, at: 200, leaseDurationMS: 10) }
        #expect(try await reopened.read { db in try String.fetchOne(db, sql: "SELECT retry_category FROM outbox WHERE mutation_id = ?", arguments: [mutationID]) } == invalid)
    }

    @Test func relaunchedReservationRejectsBackwardClockAndStaleToken() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite"), keys = StateValidationKeys()
        let original = try await TaisaStore.open(at: url, keyStore: keys)
        let mutationID = UUID().uuidString
        try await ProfileRepository(store: original).create(ProfileRecord(id: UUID().uuidString, displayName: "Name", headline: "", biography: "", updatedAtMS: 100), context: MutationContext(id: mutationID, deviceID: UUID().uuidString, timestamp: 100))
        let first = try #require(await ChangeJournal(store: original).reservePending(limit: 1, at: 200, leaseDurationMS: 10).first)
        let reopened = try await TaisaStore.open(at: url, keyStore: keys)
        let journal = ChangeJournal(store: reopened)
        #expect(try await journal.reservePending(limit: 1, at: 0, leaseDurationMS: 10).isEmpty)
        let second = try #require(await journal.reservePending(limit: 1, at: 210, leaseDurationMS: 10).first)
        #expect(second.reservationID != first.reservationID)
        #expect(second.change.retryCategory == nil)
        await #expect(throws: RepositoryError.reservationMismatch) { try await journal.retry(id: mutationID, category: "offline", reservationID: first.reservationID) }
        #expect(try await journal.state(id: mutationID) == .reserved(reservationID: second.reservationID, expiresAtMS: 220, attempts: 0))
        try await journal.retry(id: mutationID, category: "offline", reservationID: second.reservationID)
        #expect(try await journal.pending(limit: 1).first?.retryCategory == "offline")
    }
}
