import Foundation
import Testing
import TaisaCore

@Suite struct PersonalIsolationTests {
    @Test func personalHostHasIsolatedIdentityAndEnvironment() throws {
        #expect(Bundle.main.bundleIdentifier == "com.taisa.app.personal")
        let value = try #require(Bundle.main.object(forInfoDictionaryKey: "TaisaEnvironment") as? String)
        let environment = try TaisaEnvironment(configurationValue: value)
        #expect(environment == .personal)
        #expect(environment.allowsFixtures == false)
        #expect(environment.allowsLiveCloudTransport == false)
        #expect(Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") == nil)
    }
}
