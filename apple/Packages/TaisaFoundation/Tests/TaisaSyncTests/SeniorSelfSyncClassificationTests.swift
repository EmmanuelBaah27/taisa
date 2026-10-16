import Foundation
import Testing
@testable import TaisaSync

@Suite struct SeniorSelfSyncClassificationTests {
    @Test func classifiesEverySeniorSelfEntityWithoutFallback() {
        #expect(SeniorSelfSyncClassification.classify("assistant_response_metadata") == .encryptedSync)
        #expect(SeniorSelfSyncClassification.classify("assistant_response_source") == .encryptedSync)
        #expect(SeniorSelfSyncClassification.classify("assistant_proposal") == .encryptedSync)
        #expect(SeniorSelfSyncClassification.classify("response_feedback") == .localOnly)
        #expect(SeniorSelfSyncClassification.classify("preference_profile") == .localOnly)
        #expect(SeniorSelfSyncClassification.classify("unknown") == nil)
    }

    @Test func mutationValidationAllowsEncryptedCompanionsAndRejectsLocalOnlyOrUnknownEntities() throws {
        for entityType in ["assistant_response_metadata", "assistant_response_source", "assistant_proposal"] {
            #expect(throws: Never.self) { try mutation(entityType: entityType).validate() }
        }
        for entityType in ["response_feedback", "preference_profile", "unknown"] {
            #expect(throws: SyncMergeError.malformedMutation) {
                try mutation(entityType: entityType).validate()
            }
        }
    }

    private func mutation(entityType: String) -> SyncMutation {
        let mutationID = UUID().uuidString
        let deviceID = UUID().uuidString
        return .init(
            id: mutationID, entityType: entityType, entityID: UUID().uuidString,
            entityVersion: 1, deviceID: deviceID, counter: 1, timestampMS: 1,
            kind: .create,
            fields: [.init(name: "payload", value: Data(), versionID: mutationID, deviceCounter: 1)]
        )
    }
}
