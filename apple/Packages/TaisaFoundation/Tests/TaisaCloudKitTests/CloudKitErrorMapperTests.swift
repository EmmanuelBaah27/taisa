import CloudKit
import Foundation
import Testing
import TaisaCloudKit
import TaisaSync

@Suite struct CloudKitErrorMapperTests {
    @Test func cloudErrorsBecomeContentFreeSyncCategories() {
        #expect(CloudKitErrorMapper.map(CKError(.quotaExceeded)) == .quota)
        #expect(CloudKitErrorMapper.map(CKError(.notAuthenticated)) == .accountChanged)
        #expect(CloudKitErrorMapper.map(CKError(.zoneNotFound)) == .zoneReset)
        #expect(CloudKitErrorMapper.map(CKError(.changeTokenExpired)) == .tokenExpired)
        #expect(CloudKitErrorMapper.map(CKError(.networkUnavailable)) == .offline)
        let canary = "PRIVATE-CANARY-ERROR-DESCRIPTION"
        let mapped = CloudKitErrorMapper.map(NSError(domain: "private", code: 1, userInfo: [NSLocalizedDescriptionKey: canary]))
        #expect(!String(describing: mapped).contains(canary))
    }
}
