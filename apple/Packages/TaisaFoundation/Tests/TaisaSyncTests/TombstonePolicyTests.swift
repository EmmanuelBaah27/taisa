import Foundation
import Testing
import TaisaSync

@Suite struct TombstonePolicyTests {
    private let a = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    private let b = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    private let deletion = "00000000-0000-4000-8000-000000000003"
    private let day: Int64 = 86_400_000

    private func tombstone(at time: Int64 = 1, conflictIDs: [String] = []) -> SyncTombstone {
        SyncTombstone(deletionVersionID: deletion, deletedAtMS: time, frontier: VersionVector(entries: [DeviceCounter(deviceID: a, counter: 3)]), unresolvedConflictIDs: conflictIDs)
    }

    private func device(_ id: String, ack: Int64?, removed: Bool = false, removalSynced: Bool = false) -> SyncDevice {
        SyncDevice(id: id, acknowledgedFrontier: ack.map { VersionVector(entries: [DeviceCounter(deviceID: a, counter: $0)]) }, removedAtMS: removed ? 10 : nil, removalEventSynchronized: removalSynced)
    }

    @Test func ninetyDayFloorAndEveryRegisteredAcknowledgementAreRequired() {
        let devices = [device(a, ack: 4), device(b, ack: 4)]
        #expect(!TombstonePolicy.mayPurge(tombstone(), devices: devices, nowMS: 89 * day))
        #expect(TombstonePolicy.mayPurge(tombstone(), devices: devices, nowMS: 90 * day + 1))
        #expect(!TombstonePolicy.mayPurge(tombstone(), devices: [device(a, ack: 4), device(b, ack: 3)], nowMS: 90 * day + 1))
        #expect(!TombstonePolicy.mayPurge(tombstone(), devices: [device(a, ack: 4), device(b, ack: nil)], nowMS: 90 * day + 1))
    }

    @Test func unresolvedConflictBlocksPurge() {
        #expect(!TombstonePolicy.mayPurge(tombstone(conflictIDs: [deletion]), devices: [device(a, ack: 4)], nowMS: 91 * day))
    }

    @Test func removalOnlyStopsBlockingAfterSynchronizedEvent() {
        let stale = device(b, ack: nil, removed: true, removalSynced: false)
        let retired = device(b, ack: nil, removed: true, removalSynced: true)
        #expect(!TombstonePolicy.mayPurge(tombstone(), devices: [device(a, ack: 4), stale], nowMS: 91 * day))
        #expect(TombstonePolicy.mayPurge(tombstone(), devices: [device(a, ack: 4), retired], nowMS: 91 * day))
    }

    @Test func malformedIdentityCountersTimeAndRemovalFailClosed() {
        let valid = device(a, ack: 4)
        let duplicate = [valid, valid]
        let badCounter = SyncDevice(id: a, acknowledgedFrontier: VersionVector(entries: [DeviceCounter(deviceID: a, counter: -1)]), removedAtMS: nil, removalEventSynchronized: false)
        let inconsistentRemoval = SyncDevice(id: a, acknowledgedFrontier: valid.acknowledgedFrontier, removedAtMS: nil, removalEventSynchronized: true)
        let tooLate = tombstone(at: Int64.max - day)
        for (stone, devices, now) in [(tombstone(), duplicate, 91 * day), (tombstone(), [badCounter], 91 * day), (tombstone(), [inconsistentRemoval], 91 * day), (tooLate, [valid], Int64.max)] {
            #expect(!TombstonePolicy.mayPurge(stone, devices: devices, nowMS: now))
        }
    }

    @Test func vectorAcknowledgementCanKeepAnUnchangedComponent() {
        let stone = SyncTombstone(deletionVersionID: deletion, deletedAtMS: 1, frontier: VersionVector(entries: [DeviceCounter(deviceID: a, counter: 3), DeviceCounter(deviceID: b, counter: 2)]), unresolvedConflictIDs: [])
        let acknowledged = VersionVector(entries: [DeviceCounter(deviceID: a, counter: 4), DeviceCounter(deviceID: b, counter: 2)])
        let observer = SyncDevice(id: a, acknowledgedFrontier: acknowledged, removedAtMS: nil, removalEventSynchronized: false)
        #expect(TombstonePolicy.mayPurge(stone, devices: [observer], nowMS: 91 * day))
    }
}
