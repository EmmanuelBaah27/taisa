import Foundation
import GRDB
import Testing
@testable import TaisaStorage

private actor ReviewRegressionKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}

@Suite(.serialized) struct Task3ReviewRegressionTests {
    private func fixture() async throws -> (TaisaStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: ReviewRegressionKeys()), directory)
    }

    @Test func lateRemoteAcknowledgementSurvivesLocalSupersession() async throws {
        let (store, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ProfileRepository(store: store), journal = ChangeJournal(store: store)
        let id = UUID().uuidString, device = UUID().uuidString
        let created = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 100)
        let older = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 101)
        let newer = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 102)
        try await repository.create(ProfileRecord(id: id, displayName: "a", headline: "", biography: "", updatedAtMS: 100), context: created)
        try await repository.update(ProfileRecord(id: id, displayName: "b", headline: "", biography: "", updatedAtMS: 101), context: older)
        #expect(try await journal.pending(limit: 200).contains { $0.id == older.id })
        try await repository.update(ProfileRecord(id: id, displayName: "c", headline: "", biography: "", updatedAtMS: 102), context: newer)
        #expect(try await journal.supersede(olderID: older.id, by: newer.id, at: 103))
        try await journal.acknowledge(id: older.id, at: 104)
        #expect(try await store.read { db in try Int64.fetchOne(db, sql: "SELECT acknowledged_at_ms FROM outbox WHERE mutation_id = ?", arguments: [older.id]) } == 104)
        #expect(try await journal.state(id: older.id) == .superseded(by: newer.id, remotelyAcknowledgedAtMS: 104))
        #expect(try await journal.remoteCoverage(id: older.id) == .confirmed)
    }

    @Test func reservationPreventsSupersessionAndSerializesRetry() async throws {
        let (store, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ProfileRepository(store: store), journal = ChangeJournal(store: store)
        let id = UUID().uuidString, device = UUID().uuidString
        let created = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 100)
        let older = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 101)
        let newer = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 102)
        try await repository.create(ProfileRecord(id: id, displayName: "a", headline: "", biography: "", updatedAtMS: 100), context: created)
        try await journal.acknowledge(id: created.id, at: 100)
        try await repository.update(ProfileRecord(id: id, displayName: "b", headline: "", biography: "", updatedAtMS: 101), context: older)
        try await repository.update(ProfileRecord(id: id, displayName: "c", headline: "", biography: "", updatedAtMS: 102), context: newer)
        let reserved = try await journal.reservePending(limit: 1, at: 103, leaseDurationMS: 50)
        #expect(reserved.map(\.change.id) == [older.id])
        #expect(try await journal.pending(limit: 10).map(\.id) == [newer.id])
        #expect(try await journal.supersede(olderID: older.id, by: newer.id, at: 104) == false)
        #expect(try await journal.state(id: older.id) == .reserved(reservationID: reserved[0].reservationID, expiresAtMS: 153, attempts: 0))
        await #expect(throws: RepositoryError.reservationMismatch) {
            try await journal.retry(id: older.id, category: "offline", reservationID: UUID().uuidString)
        }
        try await journal.retry(id: older.id, category: "offline", reservationID: reserved[0].reservationID)
        #expect(try await journal.state(id: older.id) == .retrying(category: "offline", attempts: 1))
    }

    @Test func replacementChainAndRemoteCoverageSurviveRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite"), keys = ReviewRegressionKeys()
        let store = try await TaisaStore.open(at: url, keyStore: keys)
        let repository = ProfileRepository(store: store), journal = ChangeJournal(store: store)
        let id = UUID().uuidString, device = UUID().uuidString
        let created = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 100)
        let a = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 101)
        let b = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 102)
        let c = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 103)
        try await repository.create(ProfileRecord(id: id, displayName: "0", headline: "", biography: "", updatedAtMS: 100), context: created)
        try await journal.acknowledge(id: created.id, at: 100)
        for (context, name) in [(a, "a"), (b, "b"), (c, "c")] {
            try await repository.update(ProfileRecord(id: id, displayName: name, headline: "", biography: "", updatedAtMS: context.timestamp), context: context)
        }
        #expect(try await journal.supersede(olderID: a.id, by: b.id, at: 104))
        #expect(try await journal.supersede(olderID: b.id, by: c.id, at: 105))
        #expect(try await journal.state(id: a.id) == .superseded(by: b.id, remotelyAcknowledgedAtMS: nil))
        #expect(try await journal.remoteCoverage(id: a.id) == .waitingFor(c.id))
        let reopened = try await TaisaStore.open(at: url, keyStore: keys)
        let resumed = ChangeJournal(store: reopened)
        #expect(try await resumed.remoteCoverage(id: a.id) == .waitingFor(c.id))
        #expect(try await resumed.pending(limit: 10).map(\.id) == [c.id])
        try await resumed.acknowledge(id: c.id, at: 106)
        #expect(try await resumed.remoteCoverage(id: a.id) == .confirmed)
        #expect(try await resumed.remoteCoverage(id: b.id) == .confirmed)
        #expect(try await resumed.state(id: c.id) == .remotelyAcknowledged(atMS: 106))
    }

    @Test func expiredReservationIsReclaimableAfterRelaunchAndLateAckRecords() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite"), keys = ReviewRegressionKeys()
        let store = try await TaisaStore.open(at: url, keyStore: keys)
        let context = MutationContext(id: UUID().uuidString, deviceID: UUID().uuidString, timestamp: 100)
        try await ProfileRepository(store: store).create(ProfileRecord(id: UUID().uuidString, displayName: "a", headline: "", biography: "", updatedAtMS: 100), context: context)
        let first = try #require(await ChangeJournal(store: store).reservePending(limit: 1, at: 200, leaseDurationMS: 10).first)
        let reopened = try await TaisaStore.open(at: url, keyStore: keys)
        let journal = ChangeJournal(store: reopened)
        #expect(try await journal.reservePending(limit: 1, at: 209, leaseDurationMS: 10).isEmpty)
        let second = try #require(await journal.reservePending(limit: 1, at: 211, leaseDurationMS: 10).first)
        #expect(second.reservationID != first.reservationID)
        try await journal.acknowledge(id: context.id, at: 212)
        #expect(try await journal.state(id: context.id) == .remotelyAcknowledged(atMS: 212))
        #expect(try await journal.reservePending(limit: 1, at: 222, leaseDurationMS: 10).isEmpty)
    }

    @Test func outgoingPayloadDiffersWhenParentVersionsDiffer() async throws {
        let (firstStore, firstDirectory) = try await fixture()
        let (secondStore, secondDirectory) = try await fixture()
        defer {
            try? FileManager.default.removeItem(at: firstDirectory)
            try? FileManager.default.removeItem(at: secondDirectory)
        }
        let id = UUID().uuidString, device = UUID().uuidString
        let final = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 102)
        for (store, parentID) in [(firstStore, UUID().uuidString), (secondStore, UUID().uuidString)] {
            let repository = ProfileRepository(store: store)
            try await repository.create(ProfileRecord(id: id, displayName: "before", headline: "", biography: "", updatedAtMS: 100), context: MutationContext(id: parentID, deviceID: device, timestamp: 100))
            try await repository.update(ProfileRecord(id: id, displayName: "after", headline: "", biography: "", updatedAtMS: 102), context: final)
        }
        let first = try #require(await ChangeJournal(store: firstStore).pending(limit: 200).last?.payload)
        let second = try #require(await ChangeJournal(store: secondStore).pending(limit: 200).last?.payload)
        #expect(first != second)
    }

    @Test func coalescedSurvivorRetainsFieldLineageAndDeleteHasLogicalVersion() async throws {
        let (store, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ProfileRepository(store: store), journal = ChangeJournal(store: store)
        let id = UUID().uuidString, device = UUID().uuidString
        let created = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 100)
        let older = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 101)
        let newer = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 102)
        let deletion = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 103)
        try await repository.create(ProfileRecord(id: id, displayName: "a", headline: "", biography: "", updatedAtMS: 100), context: created)
        try await repository.update(ProfileRecord(id: id, displayName: "b", headline: "", biography: "", updatedAtMS: 101), context: older)
        try await repository.update(ProfileRecord(id: id, displayName: "c", headline: "", biography: "", updatedAtMS: 102), context: newer)
        let before = try #require(await journal.pending(limit: 10).last)
        #expect(before.causality.logicalVersionID == newer.id)
        #expect(before.causality.deviceCounter == 3)
        let display = try #require(before.causality.changedFields.first { $0.fieldName == "displayName" })
        #expect(display.parentVersionID == older.id)
        #expect(display.ancestorVersionIDs == [older.id, created.id])
        #expect(try await journal.supersede(olderID: older.id, by: newer.id, at: 104))
        let after = try #require(await journal.pending(limit: 10).last)
        #expect(after.payload == before.payload)
        try await repository.delete(id: id, context: deletion)
        let deleted = try #require(await journal.pending(limit: 10).last)
        #expect(deleted.causality.logicalVersionID == deletion.id)
        #expect(deleted.causality.recordParentVersionID == newer.id)
        #expect(deleted.causality.deviceCounter == 4)
        #expect(deleted.causality.observedFieldVersions.contains { $0.fieldName == "displayName" && $0.versionID == newer.id })
    }

    @Test func journalAcknowledgementErrorIsTypedAndContentFree() async throws {
        let (store, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = MutationContext(id: UUID().uuidString, deviceID: UUID().uuidString, timestamp: 100)
        try await ProfileRepository(store: store).create(ProfileRecord(id: UUID().uuidString, displayName: "a", headline: "", biography: "", updatedAtMS: 100), context: context)
        try await store.write { db in try db.execute(sql: "CREATE TRIGGER fail_journal BEFORE UPDATE ON outbox BEGIN SELECT RAISE(ABORT, 'PRIVATE-REVIEW-CANARY'); END") }
        do {
            try await ChangeJournal(store: store).acknowledge(id: context.id, at: 101)
            Issue.record("Injected failure was ignored")
        } catch {
            #expect(error is RepositoryError)
            #expect(!String(describing: error).contains("PRIVATE-REVIEW-CANARY"))
        }
    }

    @Test(arguments: ["retry", "supersede"])
    func journalWriteFailureIsTypedContentFreeAndRolledBack(operation: String) async throws {
        let (store, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ProfileRepository(store: store), journal = ChangeJournal(store: store)
        let id = UUID().uuidString, device = UUID().uuidString
        let created = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 100)
        let older = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 101)
        let newer = MutationContext(id: UUID().uuidString, deviceID: device, timestamp: 102)
        try await repository.create(ProfileRecord(id: id, displayName: "a", headline: "", biography: "", updatedAtMS: 100), context: created)
        try await repository.update(ProfileRecord(id: id, displayName: "b", headline: "", biography: "", updatedAtMS: 101), context: older)
        try await repository.update(ProfileRecord(id: id, displayName: "c", headline: "", biography: "", updatedAtMS: 102), context: newer)
        try await store.write { db in try db.execute(sql: "CREATE TRIGGER fail_journal BEFORE UPDATE ON outbox BEGIN SELECT RAISE(ABORT, 'PRIVATE-REVIEW-CANARY'); END") }
        do {
            if operation == "retry" { try await journal.retry(id: older.id, category: "offline") }
            else { _ = try await journal.supersede(olderID: older.id, by: newer.id, at: 103) }
            Issue.record("Injected failure was ignored")
        } catch {
            #expect(error is RepositoryError)
            #expect(!String(describing: error).contains("PRIVATE-REVIEW-CANARY"))
        }
        try await store.write { db in try db.execute(sql: "DROP TRIGGER fail_journal") }
        #expect(try await journal.pending(limit: 10).map(\.id) == [created.id, older.id, newer.id])
        let attempts = try await store.read { db in try Int.fetchOne(db, sql: "SELECT attempts FROM outbox WHERE mutation_id = ?", arguments: [older.id]) }
        #expect(attempts == 0)
    }

    @Test func journalPendingReadFailureIsTypedAndContentFree() async throws {
        let (store, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await store.write { db in try db.execute(sql: "DROP TABLE outbox") }
        do {
            _ = try await ChangeJournal(store: store).pending(limit: 1)
            Issue.record("Broken outbox read was accepted")
        } catch {
            #expect(error is RepositoryError)
            #expect(!String(describing: error).contains("SELECT"))
        }
    }

    @Test func newerJournalReadsFailTypedAndContentFree() async throws {
        let (store, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await store.write { db in try db.execute(sql: "DROP TABLE outbox") }
        let journal = ChangeJournal(store: store)
        for operation in ["state", "coverage", "reservation"] {
            do {
                switch operation {
                case "state": _ = try await journal.state(id: UUID().uuidString)
                case "coverage": _ = try await journal.remoteCoverage(id: UUID().uuidString)
                default: _ = try await journal.reservePending(limit: 1, at: 100, leaseDurationMS: 10)
                }
                Issue.record("Broken outbox \(operation) was accepted")
            } catch {
                #expect(error is RepositoryError)
                #expect(!String(describing: error).contains("SELECT"))
                #expect(!String(describing: error).contains("outbox"))
            }
        }
    }

    @Test func failedReservationRollsBackEveryClaim() async throws {
        let (store, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ProfileRepository(store: store), journal = ChangeJournal(store: store)
        let deviceID = UUID().uuidString
        for index in 0..<2 {
            try await repository.create(ProfileRecord(id: UUID().uuidString, displayName: "\(index)", headline: "", biography: "", updatedAtMS: 100), context: MutationContext(id: UUID().uuidString, deviceID: deviceID, timestamp: 100))
        }
        let before = try await journal.pending(limit: 10)
        let failedID = try #require(before.last?.id)
        try await store.write { db in try db.execute(sql: "CREATE TRIGGER fail_second_reservation BEFORE UPDATE ON outbox WHEN OLD.mutation_id = '\(failedID)' BEGIN SELECT RAISE(ABORT, 'PRIVATE-RESERVATION-CANARY'); END") }
        do {
            _ = try await journal.reservePending(limit: 2, at: 101, leaseDurationMS: 10)
            Issue.record("Injected reservation failure was ignored")
        } catch {
            #expect(error is RepositoryError)
            #expect(!String(describing: error).contains("PRIVATE-RESERVATION-CANARY"))
        }
        try await store.write { db in try db.execute(sql: "DROP TRIGGER fail_second_reservation") }
        #expect(try await journal.pending(limit: 10) == before)
    }
}
