import Foundation
import Testing
import TaisaStorage
import TaisaSync

@Suite struct MergeEngineTests {
    private let record = "11111111-1111-4111-8111-111111111111"
    private let a = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    private let b = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    private let base = "00000000-0000-4000-8000-000000000001"
    private let first = "00000000-0000-4000-8000-000000000002"
    private let second = "00000000-0000-4000-8000-000000000003"

    private func field(_ name: String, _ text: String, version: String, ancestors: [String] = [], counter: Int64 = 1) -> SyncField {
        SyncField(name: name, value: Data(text.utf8), versionID: version, ancestorVersionIDs: ancestors, deviceCounter: counter)
    }

    private func mutation(_ id: String, device: String, counter: Int64, kind: SyncMutation.Kind = .update, fields: [SyncField] = [], observed: [SyncObservedField] = [], entity: String = "goal", entityVersion: Int = 1, timestamp: Int64 = 100) -> SyncMutation {
        SyncMutation(id: id, entityType: entity, entityID: record, entityVersion: entityVersion, deviceID: device, counter: counter, timestampMS: timestamp, kind: kind, fields: fields, observedFieldVersions: observed)
    }

    @Test func newRecordAndDuplicateDelivery() throws {
        let incoming = mutation(first, device: a, counter: 1, kind: .create, fields: [field("title", "First", version: first)])
        #expect(try MergeEngine.merge(local: nil, remote: incoming).kind == .applied)
        #expect(try MergeEngine.merge(local: incoming, remote: incoming).kind == .duplicate)
    }

    @Test func appendOnlyMessageDeduplicatesAndRejectsCompetingIdentity() throws {
        let original = mutation(first, device: a, counter: 1, kind: .create, fields: [field("body", "One", version: first)], entity: "message")
        let different = mutation(second, device: b, counter: 1, kind: .create, fields: [field("body", "Two", version: second)], entity: "message")
        #expect(try MergeEngine.merge(local: original, remote: original).kind == .duplicate)
        let result = try MergeEngine.merge(local: original, remote: different)
        #expect(result.kind == .conflicted)
        #expect(Set(result.conflicts.flatMap { [$0.first.value, $0.second.value] }.compactMap { $0 }) == Set([Data("One".utf8), Data("Two".utf8)]))
    }

    @Test func appendOnlySameStableIDAndContentDeduplicatesAcrossMutationIDs() throws {
        let original = mutation(first, device: a, counter: 1, kind: .create, fields: [field("body", "Same", version: first)], entity: "message")
        let replay = mutation(second, device: b, counter: 1, kind: .create, fields: [field("body", "Same", version: second)], entity: "message")
        #expect(try MergeEngine.merge(local: original, remote: replay).kind == .duplicate)
        #expect(try MergeEngine.merge(local: replay, remote: original).kind == .duplicate)
    }

    @Test func ancestorUpdateWinsDespiteClockSkewAndOrder() throws {
        let old = mutation(first, device: a, counter: 1, fields: [field("title", "Old", version: first)], timestamp: 9000)
        let new = mutation(second, device: b, counter: 1, fields: [field("title", "New", version: second, ancestors: [first])], timestamp: 1)
        for pair in [(old, new), (new, old)] {
            let result = try MergeEngine.merge(local: pair.0, remote: pair.1)
            #expect(result.kind == .merged)
            #expect(result.fields.map(\.value) == [Data("New".utf8)])
            #expect(result.conflicts.isEmpty)
        }
    }

    @Test func nonOverlappingEditsMergeInEitherDeliveryOrder() throws {
        let title = mutation(first, device: a, counter: 1, fields: [field("title", "A", version: first)])
        let detail = mutation(second, device: b, counter: 1, fields: [field("detail", "B", version: second)])
        let forward = try MergeEngine.merge(local: title, remote: detail)
        let reverse = try MergeEngine.merge(local: detail, remote: title)
        #expect(forward == reverse)
        #expect(forward.fields.map(\.name) == ["detail", "title"])
    }

    @Test func sameFieldConcurrentEditsPreserveBothValuesAndLineage() throws {
        let left = mutation(first, device: a, counter: 1, fields: [field("title", "Left", version: first, ancestors: [base])])
        let right = mutation(second, device: b, counter: 1, fields: [field("title", "Right", version: second, ancestors: [base])])
        let forward = try MergeEngine.merge(local: left, remote: right)
        let reverse = try MergeEngine.merge(local: right, remote: left)
        #expect(forward == reverse)
        #expect(forward.kind == .conflicted)
        #expect(forward.fields.isEmpty)
        #expect(forward.conflicts.count == 1)
        #expect(forward.conflicts[0].first.versionID == first)
        #expect(forward.conflicts[0].first.value == Data("Left".utf8))
        #expect(forward.conflicts[0].second.versionID == second)
        #expect(forward.conflicts[0].second.value == Data("Right".utf8))
        #expect(forward.conflicts[0].first.ancestorVersionIDs == [base])
    }

    @Test func deleteVersusEditKeepsDeletionAndCompetingValue() throws {
        let edit = mutation(first, device: a, counter: 1, fields: [field("title", "Offline", version: first)])
        let deletion = mutation(second, device: b, counter: 1, kind: .delete)
        let decision = try MergeEngine.merge(local: edit, remote: deletion)
        #expect(decision.kind == .deletedWithConflicts)
        #expect(decision.deletion?.id == second)
        #expect(decision.conflicts[0].first.value == Data("Offline".utf8))
        #expect(decision.conflicts[0].second.value == nil)
        #expect(try MergeEngine.merge(local: deletion, remote: edit) == decision)
    }

    @Test func observedEditDeletedAfterItDoesNotCreateConflict() throws {
        let edit = mutation(first, device: a, counter: 1, fields: [field("title", "Old", version: first)])
        let deletion = mutation(second, device: b, counter: 1, kind: .delete, observed: [SyncObservedField(name: "title", versionID: first)])
        let decision = try MergeEngine.merge(local: edit, remote: deletion)
        #expect(decision.kind == .deleted)
        #expect(decision.conflicts.isEmpty)
    }

    @Test func staleOfflineDescendantOfObservedVersionStillConflictsWithDeletion() throws {
        let edit = mutation(first, device: a, counter: 2, fields: [field("title", "Offline", version: first, ancestors: [base], counter: 2)])
        let deletion = mutation(second, device: b, counter: 1, kind: .delete, observed: [SyncObservedField(name: "title", versionID: base)])
        let result = try MergeEngine.merge(local: edit, remote: deletion)
        #expect(result.kind == .deletedWithConflicts)
        #expect(try #require(result.conflicts.first).first.value == Data("Offline".utf8))
    }

    @Test func appendOnlyFieldNamesArePairedByNameIndependentOfOrder() throws {
        let left = mutation(first, device: a, counter: 1, kind: .create, fields: [field("z", "Z", version: first), field("a", "A", version: first)], entity: "message")
        let right = mutation(second, device: b, counter: 1, kind: .create, fields: [field("b", "B", version: second), field("a", "Other", version: second)], entity: "message")
        let forward = try MergeEngine.merge(local: left, remote: right)
        let reverse = try MergeEngine.merge(local: right, remote: left)
        #expect(forward == reverse)
        #expect(forward.conflicts.map(\.fieldName) == ["a", "b", "z"])
        #expect(Set(forward.conflicts[0].first.value.map { [$0] } ?? []).union(forward.conflicts[0].second.value.map { [$0] } ?? []) == Set([Data("A".utf8), Data("Other".utf8)]))
    }

    @Test func duplicateDeviceIdentitiesDifferingOnlyByCaseFailClosed() throws {
        let duplicated = VersionVector(entries: [DeviceCounter(deviceID: a, counter: 1), DeviceCounter(deviceID: a.uppercased(), counter: 2)])
        let incoming = SyncMutation(id: first, entityType: "goal", entityID: record, entityVersion: 1, deviceID: a, counter: 1, timestampMS: 1, kind: .update, fields: [field("title", "A", version: first)], frontier: duplicated)
        #expect(throws: SyncMergeError.self) { try MergeEngine.merge(local: nil, remote: incoming) }
    }

    @Test func causalAncestryUsesCanonicalUUIDIdentity() throws {
        let oldID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        let newID = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
        let older = mutation(oldID, device: a, counter: 1, fields: [field("title", "Older", version: oldID)])
        let newer = mutation(newID, device: b, counter: 1, fields: [field("title", "Newer", version: newID, ancestors: [oldID.uppercased()])])
        #expect(try MergeEngine.merge(local: older, remote: newer).fields.map(\.value) == [Data("Newer".utf8)])
        let selfAncestor = mutation(newID, device: b, counter: 1, fields: [field("title", "Bad", version: newID, ancestors: [newID.uppercased()])])
        #expect(throws: SyncMergeError.self) { try MergeEngine.merge(local: nil, remote: selfAncestor) }
    }

    @Test func deleteDeleteConvergesWithoutResurrection() throws {
        let left = mutation(first, device: a, counter: 1, kind: .delete)
        let right = mutation(second, device: b, counter: 1, kind: .delete)
        #expect(try MergeEngine.merge(local: left, remote: right) == MergeEngine.merge(local: right, remote: left))
        #expect(try MergeEngine.merge(local: left, remote: right).kind == .deleted)
    }

    @Test func resolutionReferencesBothParentsAndCanBecomeOutgoingJournalCausality() throws {
        let left = mutation(first, device: a, counter: 1, fields: [field("title", "Left", version: first)])
        let right = mutation(second, device: b, counter: 1, fields: [field("title", "Right", version: second)])
        let conflict = try MergeEngine.merge(local: left, remote: right).conflicts[0]
        let resolutionID = "00000000-0000-4000-8000-000000000004"
        let resolved = try conflict.resolve(value: Data("Chosen".utf8), mutationID: resolutionID, deviceID: a, counter: 2, timestampMS: 20)
        #expect(Set(resolved.fields[0].ancestorVersionIDs) == Set([first, second]))
        #expect(resolved.kind == .resolve)
        let snapshot = try resolved.journalCausality()
        #expect(snapshot.logicalVersionID == resolutionID)
        #expect(Set(snapshot.changedFields[0].ancestorVersionIDs) == Set([first, second]))
        #expect(try MergeEngine.merge(local: left, remote: resolved).conflicts.isEmpty)
        #expect(try MergeEngine.merge(local: right, remote: resolved).conflicts.isEmpty)
    }

    @Test func explicitDeleteConflictResolutionCanRestoreChosenValue() throws {
        let edit = mutation(first, device: a, counter: 1, fields: [field("title", "Keep", version: first)])
        let deletion = mutation(second, device: b, counter: 1, kind: .delete)
        let conflict = try #require(MergeEngine.merge(local: edit, remote: deletion).conflicts.first)
        let resolutionID = "00000000-0000-4000-8000-000000000004"
        let resolved = try conflict.resolve(value: Data("Keep".utf8), mutationID: resolutionID, deviceID: a, counter: 2, timestampMS: 20)
        let result = try MergeEngine.merge(local: deletion, remote: resolved)
        #expect(result.kind == .merged)
        #expect(result.deletion == nil)
        #expect(result.fields.map(\.value) == [Data("Keep".utf8)])
    }

    @Test func claimedResolutionWithoutBothParentsCannotClearDeletion() throws {
        let deletion = mutation(second, device: b, counter: 1, kind: .delete)
        let resolutionID = "00000000-0000-4000-8000-000000000004"
        let incomplete = mutation(resolutionID, device: a, counter: 2, kind: .resolve, fields: [field("title", "Claimed", version: resolutionID, ancestors: [second], counter: 2)])
        #expect(throws: SyncMergeError.self) { try MergeEngine.merge(local: deletion, remote: incomplete) }
    }

    @Test func pairwisePermutationsKeepDecisionStableAcrossIdentifiersAndClockSkew() throws {
        for index in 10..<80 {
            let leftID = String(format: "00000000-0000-4000-8000-%012d", index)
            let rightID = String(format: "00000000-0000-4000-8000-%012d", index + 100)
            let left = mutation(leftID, device: a, counter: Int64(index), fields: [field("title", "A", version: leftID, counter: Int64(index))], timestamp: 10_000)
            let right = mutation(rightID, device: b, counter: Int64(index), fields: [field("title", "B", version: rightID, counter: Int64(index))], timestamp: 0)
            #expect(try MergeEngine.merge(local: left, remote: right) == MergeEngine.merge(local: right, remote: left))
        }
    }

    @Test func unknownVersionAndMalformedCountersFailClosedWithoutContentInErrors() throws {
        let good = mutation(first, device: a, counter: 1, fields: [field("title", "PRIVATE-CANARY", version: first)])
        let badVersion = mutation(second, device: b, counter: 1, entityVersion: 99)
        let badCounter = mutation(second, device: b, counter: -1)
        for bad in [badVersion, badCounter] {
            do { _ = try MergeEngine.merge(local: good, remote: bad); Issue.record("invalid mutation accepted") }
            catch { #expect(!String(describing: error).contains("PRIVATE-CANARY")) }
        }
    }

    @Test func duplicateDeviceCounterAndIdentityMismatchFailClosed() throws {
        let local = mutation(first, device: a, counter: 1, fields: [field("title", "One", version: first)])
        let reusedCounter = mutation(second, device: a, counter: 1, fields: [field("detail", "Two", version: second)])
        let otherRecord = SyncMutation(id: second, entityType: "goal", entityID: "22222222-2222-4222-8222-222222222222", entityVersion: 1, deviceID: b, counter: 1, timestampMS: 1, kind: .update, fields: [])
        #expect(throws: SyncMergeError.self) { try MergeEngine.merge(local: local, remote: reusedCounter) }
        #expect(throws: SyncMergeError.self) { try MergeEngine.merge(local: local, remote: otherRecord) }
    }

    @Test func compatibleJournalSnapshotRetainsFieldAncestry() throws {
        let snapshot = try JSONDecoder().decode(CausalSnapshot.self, from: Data("{\"logicalVersionID\":\"\(first)\",\"recordParentVersionID\":\"\(base)\",\"deviceID\":\"\(a)\",\"deviceCounter\":7,\"changedFields\":[{\"fieldName\":\"title\",\"versionID\":\"\(first)\",\"parentVersionID\":\"\(base)\",\"ancestorVersionIDs\":[\"\(base)\"],\"deviceCounter\":7}],\"observedFieldVersions\":[{\"fieldName\":\"title\",\"versionID\":\"\(base)\"}]}".utf8))
        let incoming = try SyncMutation(id: first, entityType: "goal", entityID: record, entityVersion: 1, timestampMS: 7, kind: .update, fieldValues: ["title": Data("Value".utf8)], causality: snapshot)
        #expect(incoming.fields[0].ancestorVersionIDs == [base])
        #expect(try MergeEngine.merge(local: nil, remote: incoming).kind == .applied)
        #expect(try incoming.journalCausality().recordParentVersionID == base)
        #expect(throws: SyncMergeError.self) {
            try SyncMutation(id: first, entityType: "goal", entityID: record, entityVersion: 1, timestampMS: 7, kind: .update, fieldValues: [:], causality: snapshot)
        }
    }
}
