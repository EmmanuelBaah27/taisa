import CloudKit
import Foundation
import Testing
import TaisaCloudKit
import TaisaSync

@Suite struct CloudKitErrorMapperTests {
    @Test func zoneBusyRetainsServerRetryDeadline() {
        let error = CKError(.zoneBusy, userInfo: [CKErrorRetryAfterKey: NSNumber(value: 60)])
        #expect(CloudKitErrorMapper.map(error, nowMS: 1_000) == .rateLimited(retryAfterMS: 61_000))
        let internalRetry = CKError(.internalError, userInfo: [CKErrorRetryAfterKey: NSNumber(value: 2.5)])
        #expect(CloudKitErrorMapper.map(internalRetry, nowMS: 1_000) == .rateLimited(retryAfterMS: 3_500))
        #expect(CloudKitErrorMapper.map(CKError(.serviceUnavailable), nowMS: 1_000) == .rateLimited(retryAfterMS: 2_000))
        #expect(CloudKitErrorMapper.map(error, nowMS: Int64.max - 10) == .rateLimited(retryAfterMS: Int64.max))
        let extremeRetry = CKError(.zoneBusy, userInfo: [CKErrorRetryAfterKey: NSNumber(value: Double(Int64.max))])
        #expect(CloudKitErrorMapper.map(extremeRetry, nowMS: 0) == .rateLimited(retryAfterMS: Int64.max))
    }

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
