import Foundation
import Testing
import TaisaSync

@Suite struct MergeStateTests {
    private let entity = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
    private let a = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    private let b = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    private let c = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    private func id(_ n: Int) -> String { String(format: "dddddddd-dddd-4ddd-8ddd-%012d", n) }

    private func mutation(_ n: Int, device: String, counter: Int64, field: String, value: String, ancestors: [String] = []) -> SyncMutation {
        SyncMutation(id: id(n), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: device, counter: counter, timestampMS: Int64(n), kind: .update, fields: [SyncField(name: field, value: Data(value.utf8), versionID: id(n), ancestorVersionIDs: ancestors, deviceCounter: counter)])
    }

    @Test func threeEventPermutationsConvergeAndReplayIsFixedPoint() throws {
        let title = mutation(1, device: a, counter: 1, field: "title", value: "A")
        let detail = mutation(2, device: b, counter: 1, field: "detail", value: "B")
        let titleNext = mutation(3, device: c, counter: 1, field: "title", value: "C", ancestors: [id(1)])
        let expected = try MergeEngine.reduce(events: [title, detail, titleNext])
        #expect(expected.fields.map(\.name) == ["detail", "title"])
        #expect(expected.fields.map(\.value) == [Data("B".utf8), Data("C".utf8)])
        for events in [[title, titleNext, detail], [detail, title, titleNext], [detail, titleNext, title], [titleNext, title, detail], [titleNext, detail, title]] {
            let result = try MergeEngine.reduce(events: events)
            #expect(result == expected)
            #expect(try MergeEngine.merge(state: result.state, remote: title).state == expected.state)
            #expect(try MergeEngine.merge(state: result.state, remote: detail).state == expected.state)
            #expect(try MergeEngine.merge(state: result.state, remote: titleNext).state == expected.state)
        }
    }

    @Test func fourWayConcurrentHeadsRemainVisibleAfterEveryOrder() throws {
        let root = mutation(1, device: a, counter: 1, field: "title", value: "Root")
        let branches = [
            mutation(2, device: a, counter: 2, field: "title", value: "A", ancestors: [id(1)]),
            mutation(3, device: b, counter: 1, field: "title", value: "B", ancestors: [id(1)]),
            mutation(4, device: c, counter: 1, field: "title", value: "C", ancestors: [id(1)]),
        ]
        let expected = try MergeEngine.reduce(events: [root] + branches)
        #expect(expected.kind == .conflicted)
        #expect(Set(expected.conflicts.flatMap { [$0.first.value, $0.second.value] }.compactMap { $0 }) == Set([Data("A".utf8), Data("B".utf8), Data("C".utf8)]))
        for shift in 0..<4 {
            let all = [root] + branches
            let order = Array(all[shift...] + all[..<shift])
            #expect(try MergeEngine.reduce(events: order) == expected)
        }
    }

    @Test func concurrentDeletionsRetainAllEvidenceAndConverge() throws {
        let left = SyncMutation(id: id(1), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: a, counter: 3, timestampMS: 1, kind: .delete, fields: [], observedFieldVersions: [SyncObservedField(name: "title", versionID: id(3))])
        let right = SyncMutation(id: id(2), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: b, counter: 7, timestampMS: 100, kind: .delete, fields: [], observedFieldVersions: [SyncObservedField(name: "detail", versionID: id(4))])
        for events in [[left, right], [right, left]] {
            let result = try MergeEngine.reduce(events: events)
            let deletion = try #require(result.deletion)
            #expect(deletion.eventIDs.count == 2)
            #expect(deletion.timestampMS == 100)
            #expect(deletion.frontier.counter(for: a) == 3)
            #expect(deletion.frontier.counter(for: b) == 7)
            #expect(Set(deletion.observedFieldVersions.map(\.name)) == Set(["title", "detail"]))
            #expect(try MergeEngine.merge(state: result.state, remote: left).state == result.state)
        }
    }

    @Test func contradictoryFrontierFailsClosed() throws {
        let ancestor = mutation(1, device: b, counter: 5, field: "title", value: "Old")
        let child = SyncMutation(id: id(2), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: a, counter: 2, timestampMS: 2, kind: .update, fields: [SyncField(name: "title", value: Data("New".utf8), versionID: id(2), ancestorVersionIDs: [id(1)], deviceCounter: 2)], frontier: VersionVector(entries: [DeviceCounter(deviceID: a, counter: 2), DeviceCounter(deviceID: b, counter: 4)]))
        #expect(throws: SyncMergeError.self) { try MergeEngine.reduce(events: [ancestor, child]) }
    }

    @Test func explicitKeepDeletionCarriesBothBranchesAndReplays() throws {
        let edit = mutation(1, device: a, counter: 1, field: "title", value: "Keep")
        let deletion = SyncMutation(id: id(2), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: b, counter: 1, timestampMS: 2, kind: .delete, fields: [])
        let conflict = try #require(MergeEngine.merge(local: edit, remote: deletion).conflicts.first)
        let resolution = try conflict.resolveKeepingDeletion(mutationID: id(3), deviceID: a, counter: 2, timestampMS: 3)
        let snapshot = try resolution.journalCausality()
        #expect(Set(snapshot.resolvedParentVersionIDs ?? []) == Set([UUID(uuidString: id(1))!.uuidString, UUID(uuidString: id(2))!.uuidString]))
        let restored = try SyncMutation(id: id(3), entityType: "goal", entityID: entity, entityVersion: 1, timestampMS: 3, kind: .delete, fieldValues: [:], causality: snapshot)
        let merged = try MergeEngine.reduce(events: [edit, deletion, restored])
        #expect(merged.kind == .deleted)
        #expect(merged.conflicts.isEmpty)
        #expect(merged.deletion?.eventIDs == [UUID(uuidString: id(3))!.uuidString])
    }

    @Test func recordOrderWithoutFieldAncestryDoesNotSilenceConcurrentField() throws {
        let old = mutation(1, device: a, counter: 1, field: "title", value: "A")
        let newer = SyncMutation(id: id(2), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: b, counter: 1, timestampMS: 2, kind: .update, fields: [SyncField(name: "title", value: Data("B".utf8), versionID: id(2), deviceCounter: 1)], recordParentVersionID: id(1))
        #expect(try MergeEngine.reduce(events: [old, newer]).kind == .conflicted)
    }

    @Test func generatedFiveEventOrderingsReachSameFixedPoint() throws {
        for seed in 10..<45 {
            let base = mutation(seed, device: a, counter: Int64(seed), field: "title", value: "base")
            let titleA = mutation(seed + 100, device: a, counter: Int64(seed + 1), field: "title", value: "A", ancestors: [id(seed)])
            let titleB = mutation(seed + 200, device: b, counter: Int64(seed), field: "title", value: "B", ancestors: [id(seed)])
            let detail = mutation(seed + 300, device: c, counter: Int64(seed), field: "detail", value: "D")
            let detailNext = mutation(seed + 400, device: c, counter: Int64(seed + 1), field: "detail", value: "E", ancestors: [id(seed + 300)])
            let events = [base, titleA, titleB, detail, detailNext]
            let expected = try MergeEngine.reduce(events: events)
            for shift in events.indices {
                let rotated = Array(events[shift...]) + Array(events[..<shift])
                for order in [rotated, Array(rotated.reversed())] {
                    let current = try MergeEngine.reduce(events: order)
                    #expect(current == expected)
                    #expect(try MergeEngine.merge(state: current.state, remote: titleA).state == expected.state)
                }
            }
        }
    }

    @Test func partialFieldResolutionCannotReviveDeletedRecord() throws {
        let deletion = SyncMutation(id: id(1), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: a, counter: 1, timestampMS: 1, kind: .delete, fields: [])
        let claimed = SyncMutation(id: id(2), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: b, counter: 1, timestampMS: 2, kind: .resolve, fields: [
            SyncField(name: "title", value: Data("T".utf8), versionID: id(2), ancestorVersionIDs: [id(1), id(3)], deviceCounter: 1),
            SyncField(name: "detail", value: Data("D".utf8), versionID: id(2), ancestorVersionIDs: [id(3), id(4)], deviceCounter: 1),
        ])
        let result = try MergeEngine.reduce(events: [deletion, claimed])
        #expect(result.deletion != nil)
        #expect(result.kind == .deletedWithConflicts)
    }

    @Test func encodedMergeStateRevalidatesOnDecode() throws {
        let left = mutation(1, device: a, counter: 1, field: "title", value: "A")
        let right = mutation(2, device: b, counter: 1, field: "detail", value: "B")
        let state = try MergeEngine.reduce(events: [left, right]).state
        let payload = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(SyncMergeState.self, from: payload) == state)
        let invalid = try JSONEncoder().encode([left, SyncMutation(id: id(3), entityType: "goal", entityID: entity, entityVersion: 1, deviceID: a, counter: 1, timestampMS: 3, kind: .update, fields: [SyncField(name: "title", value: Data("C".utf8), versionID: id(3), deviceCounter: 1)])])
        #expect(throws: SyncMergeError.self) { try JSONDecoder().decode(SyncMergeState.self, from: invalid) }
    }
}
