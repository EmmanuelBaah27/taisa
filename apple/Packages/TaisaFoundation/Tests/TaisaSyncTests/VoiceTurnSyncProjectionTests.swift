import Foundation
import Testing
import TaisaStorage
@testable import TaisaSync

struct VoiceTurnSyncProjectionTests {
    @Test func projectionAcceptsDurableTurnWithoutLocalAudioFields() throws {
        let payload = try payload(recordOverride: nil)
        let projection = try SyncProjection(payload)

        #expect(projection.mutation.entityType == "voice_turn")
        #expect(!String(decoding: projection.payload, as: UTF8.self).contains("audioFileID"))
    }

    @Test func projectionRejectsAnyLocalAudioField() throws {
        let payload = try payload(recordOverride: ["audioFileID": "PRIVATE-LOCAL-AUDIO"])
        #expect(throws: SyncMergeError.self) { _ = try SyncProjection(payload) }
    }

    private func payload(recordOverride: [String: Any]?) throws -> Data {
        let mutationID = "00000000-0000-0000-0000-000000000301"
        let turnID = "00000000-0000-0000-0000-000000000302"
        let deviceID = "00000000-0000-0000-0000-000000000303"
        let turn = VoiceTurnRecord(
            id: turnID,
            conversationID: "00000000-0000-0000-0000-000000000304",
            transcriptionRequestID: "00000000-0000-0000-0000-000000000305",
            transcriptionIdempotencyKey: "transcription-key",
            coachingRequestID: "00000000-0000-0000-0000-000000000306",
            coachingIdempotencyKey: "coaching-key",
            state: .queued, stage: .transcription, retryCount: 0,
            cleanupState: .pending, createdAtMS: 1, updatedAtMS: 1
        )
        var record = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(turn)) as? [String: Any]
        )
        record.removeValue(forKey: "audioFileID")
        record.removeValue(forKey: "audioSHA256")
        record.removeValue(forKey: "audioDurationMS")
        for (key, value) in recordOverride ?? [:] { record[key] = value }
        let fields = [
            "conversationID", "transcriptionRequestID", "transcriptionIdempotencyKey",
            "coachingRequestID", "coachingIdempotencyKey", "state", "stage", "retryCount",
            "cleanupState", "createdAtMS", "updatedAtMS",
        ].map {
            ["fieldName": $0, "versionID": mutationID, "ancestorVersionIDs": [], "deviceCounter": 1] as [String: Any]
        }
        let object: [String: Any] = [
            "id": mutationID, "deviceID": deviceID, "timestamp": 1,
            "entityType": "voice_turn", "entityID": turnID, "operation": "create",
            "record": record,
            "causality": [
                "logicalVersionID": mutationID, "deviceID": deviceID, "deviceCounter": 1,
                "changedFields": fields, "observedFieldVersions": [],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
