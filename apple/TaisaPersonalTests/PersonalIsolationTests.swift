import Foundation
import Testing
import TaisaCore
@testable import TaisaPersonal

@Suite struct PersonalIsolationTests {
    @Test func personalRecoveryOpensDeviceProtectedStore() async throws {
        let backend = try PersonalRecoveryBackend.personal()
        _ = try await backend.openStore()
    }
    @Test func personalHostHasIsolatedIdentityAndEnvironment() throws {
        #expect(Bundle.main.bundleIdentifier == "com.taisa.app.personal")
        let value = try #require(Bundle.main.object(forInfoDictionaryKey: "TaisaEnvironment") as? String)
        let environment = try TaisaEnvironment(configurationValue: value)
        #expect(environment == .personal)
        #expect(environment.allowsFixtures == false)
        #expect(environment.allowsLiveCloudTransport == false)
        #expect(Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") == nil)
    }

    @Test @MainActor func personalHostDisplaysLocalStorageWithoutCloudKit() throws {
        let value = try #require(Bundle.main.object(forInfoDictionaryKey: "TaisaEnvironment") as? String)
        let environment = try TaisaEnvironment(configurationValue: value)
        #expect(environment == .personal)
        #expect(SyncCapability.forEnvironment(environment) == .localOnly)
        #expect(FoundationRootView().storageStatus == "Stored securely on this device")
        #expect(CloudKitRuntimeConfiguration.containerIdentifier(for: "com.taisa.app.personal") == nil)
    }
}
