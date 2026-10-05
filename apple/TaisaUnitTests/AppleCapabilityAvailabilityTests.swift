import AuthenticationServices
import CloudKit
import CryptoKit
import Foundation
import Security
import XCTest

final class AppleCapabilityAvailabilityTests: XCTestCase {
    func testNativeSecurityAndSyncFrameworksAreAvailable() {
        _ = CKRecord.ID(recordName: "availability-probe")
        var randomByte = [UInt8](repeating: 0, count: 1)
        XCTAssertEqual(SecRandomCopyBytes(kSecRandomDefault, 1, &randomByte), errSecSuccess)
        XCTAssertEqual(Array(SHA256.hash(data: Data())).count, 32)
        _ = ASAuthorizationPasswordProvider()
        _ = ASPasswordCredential(user: "availability-probe", password: "availability-probe")
    }

    // Enable this compile check when the installed SDK declares both types.
    // Xcode 26.1 does not, even though current Apple documentation lists them.
    // The older supported path uses explicit manual saving and confirmation.
    #if TAISA_HAS_CREDENTIAL_DATA_MANAGER_SDK
    @available(iOS 26, *)
    private func saveToPreferredManager(
        _ manager: ASCredentialDataManager,
        credential: ASPasswordCredential,
        scope: ASAutoFillURLScope
    ) async throws {
        try await manager.save(password: credential, for: scope, title: "Taisa Recovery")
    }
    #endif
}
