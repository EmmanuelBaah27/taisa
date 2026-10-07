import Foundation
import Testing
import TaisaSync
import TaisaStorage

private actor ReviewKeys: DatabaseKeyStore {
    var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ value: Data) async throws { key = value }
}

@Suite struct IndependentTask5ReviewTests {
    let entity = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
    let a = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    let b = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    let c = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    func id(_ n: Int) -> String { String(format: "dddddddd-dddd-4ddd-8ddd-%012d", n) }
    func mutation(_ n: Int, device: String? = nil, counter: Int64 = 1, ancestors: [String] = [], name: String = "title", kind: SyncMutation.Kind = .update, type: String = "goal", entityID: String? = nil) -> SyncMutation {
        SyncMutation(id: id(n), entityType: type, entityID: entityID ?? entity, entityVersion: 1, deviceID: device ?? a, counter: counter, timestampMS: 1, kind: kind, fields: kind == .delete ? [] : [SyncField(name: name, value: Data("value-\(n)".utf8), versionID: id(n), ancestorVersionIDs: ancestors, deviceCounter: counter)])
    }
    @Test func resolutionRetainsTransitiveAncestry() throws {
        let base = mutation(1)
        let left = mutation(2, counter: 2, ancestors: [id(1)])
        let right = mutation(3, device: b, ancestors: [id(1)])
        let conflict = try MergeEngine.merge(local: left, remote: right).conflicts[0]
        let resolved = try conflict.resolve(value: Data("chosen".utf8), mutationID: id(4), deviceID: a, counter: 3, timestampMS: 2)
        #expect(try MergeEngine.merge(local: resolved, remote: base).conflicts.isEmpty)
        #expect(try resolved.journalCausality().changedFields[0].ancestorVersionIDs.contains { UUID(uuidString: $0) == UUID(uuidString: id(1)) })
    }
    @Test func cyclicAncestryFailsClosed() throws {
        let left = mutation(1, ancestors: [id(2)])
        let right = mutation(2, device: b, ancestors: [id(1)])
        #expect(throws: SyncMergeError.self) { try MergeEngine.merge(local: left, remote: right) }
        #expect(throws: SyncMergeError.self) { try MergeEngine.merge(local: right, remote: left) }
    }
    @Test func regressingDeviceCounterFailsClosed() throws {
        let old = mutation(1, counter: 8)
        let impossible = mutation(2, counter: 2, ancestors: [id(1)])
        #expect(throws: SyncMergeError.self) { try MergeEngine.merge(local: old, remote: impossible) }
    }
    @Test func appendOnlyUpdateRejectedWithoutExistingRecord() throws {
        for type in ["message", "memory_source"] {
            #expect(throws: SyncMergeError.self) { try MergeEngine.merge(local: nil, remote: mutation(1, type: type)) }
        }
    }
    @Test func uuidCaseEquivalentReplayIsIdempotent() throws {
        let lower = mutation(1)
        let data = try JSONEncoder().encode(lower)
        let upper = try JSONDecoder().decode(SyncMutation.self, from: Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: a, with: a.uppercased()).replacingOccurrences(of: id(1), with: id(1).uppercased()).replacingOccurrences(of: entity, with: entity.uppercased()).utf8))
        #expect(try MergeEngine.merge(local: lower, remote: upper).kind == .duplicate)
    }
    @Test func entityCasingDoesNotBreakConflictCommutativity() throws {
        let left = mutation(1)
        let right = mutation(2, device: b, entityID: entity.uppercased())
        #expect(try MergeEngine.merge(local: left, remote: right) == MergeEngine.merge(local: right, remote: left))
    }
    @Test func mergedStateCanBeReplayed() throws {
        let left = mutation(1)
        let right = mutation(2, device: b, name: "detail")
        let merged = try MergeEngine.merge(local: left, remote: right)
        #expect(try MergeEngine.merge(state: merged.state, remote: left).state == merged.state)
    }
    @Test func task3NoOpMutationCanBeAdapted() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("review.sqlite")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await TaisaStore.open(at: url, keyStore: ReviewKeys())
        let repository = GoalRepository(store: store)
        let record = GoalRecord(id: entity, title: "Goal", detail: "Detail", status: "active", createdAtMS: 1, updatedAtMS: 1)
        try await repository.create(record, context: MutationContext(id: id(1), deviceID: a, timestamp: 1))
        try await repository.update(record, context: MutationContext(id: id(2), deviceID: a, timestamp: 2))
        let pending = try await ChangeJournal(store: store).pending(limit: 10)
        let noOp = try #require(pending.first { UUID(uuidString: $0.id) == UUID(uuidString: id(2)) })
        #expect(noOp.causality.changedFields.isEmpty)
        let adapted = try SyncMutation(id: id(2), entityType: "goal", entityID: entity, entityVersion: 1, timestampMS: 2, kind: .update, fieldValues: [:], causality: noOp.causality)
        #expect(try MergeEngine.merge(local: nil, remote: adapted).kind == .noOp)
        #expect(try adapted.journalCausality().changedFields.isEmpty)
    }
    @Test func persistedConflictCanonicalReplayIsIdempotent() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("review.sqlite")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await TaisaStore.open(at: url, keyStore: ReviewKeys())
        let conflicts = ConflictStore(store: store)
        let conflict = try MergeEngine.merge(local: mutation(1), remote: mutation(2, device: b)).conflicts[0]
        let canonical = SyncConflict(entityType: conflict.entityType, entityID: conflict.entityID.uppercased(), fieldName: conflict.fieldName, first: ConflictingValue(versionID: conflict.first.versionID.uppercased(), ancestorVersionIDs: [], value: conflict.first.value), second: ConflictingValue(versionID: conflict.second.versionID.uppercased(), ancestorVersionIDs: [], value: conflict.second.value))
        try await conflicts.persist(conflict, at: 1)
        try await conflicts.persist(canonical, at: 1)
        #expect(try await conflicts.unresolved().count == 1)
    }
    @Test func invalidConflictPayloadFailsClosed() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("review.sqlite")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await TaisaStore.open(at: url, keyStore: ReviewKeys())
        let invalid = SyncConflict(entityType: "unknown", entityID: entity, fieldName: "title", first: ConflictingValue(versionID: id(1), ancestorVersionIDs: ["not-a-version"], value: Data()), second: ConflictingValue(versionID: id(2), ancestorVersionIDs: [], value: nil))
        await #expect(throws: SyncMergeError.self) { try await ConflictStore(store: store).persist(invalid, at: 1) }
    }
    @Test func freshDeletionCannotBePurgedThroughOlderDeletion() throws {
        let old = mutation(1, kind: .delete)
        let new = SyncMutation(id: id(2), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: b, counter: 1, timestampMS: 90 * 86_400_000, kind: .delete, fields: [])
        let decision = try MergeEngine.merge(local: old, remote: new)
        let deletion = try #require(decision.deletion)
        let stone = SyncTombstone(deletionVersionID: deletion.id, deletedAtMS: deletion.timestampMS, frontier: deletion.frontier, unresolvedConflictIDs: [])
        let devices = [a, b].map { SyncDevice(id: $0, acknowledgedFrontier: VersionVector(entries: [DeviceCounter(deviceID: a, counter: 2)]), removedAtMS: nil, removalEventSynchronized: false) }
        #expect(!TombstonePolicy.mayPurge(stone, devices: devices, nowMS: 91 * 86_400_000))
    }
    @Test func vectorAdvanceOnNewDeviceIsBeyond() {
        let before = VersionVector(entries: [DeviceCounter(deviceID: a, counter: 3)])
        let after = VersionVector(entries: [DeviceCounter(deviceID: a, counter: 3), DeviceCounter(deviceID: b, counter: 1)])
        #expect(after.isBeyond(before))
    }
}
