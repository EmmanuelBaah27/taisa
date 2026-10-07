import Testing
@testable import TaisaCore

@Suite struct TaisaEnvironmentTests {
    @Test func personalEnvironmentIsIsolatedFromFixturesAndLiveCloudTransport() throws {
        let environment = try TaisaEnvironment(configurationValue: "personal")
        #expect(environment == .personal)
        #expect(environment.allowsFixtures == false)
        #expect(environment.allowsLiveCloudTransport == false)
    }

    @Test func onlyLiveEnvironmentsAllowLiveCloudTransport() {
        #expect(TaisaEnvironment.development.allowsLiveCloudTransport)
        #expect(TaisaEnvironment.production.allowsLiveCloudTransport)
        #expect(TaisaEnvironment.preview.allowsLiveCloudTransport == false)
    }

    @Test func environmentRejectsUnknownConfiguration() {
        #expect(throws: TaisaEnvironmentError.self) {
            try TaisaEnvironment(configurationValue: "staging")
        }
    }

    @Test func productionIsNotFixtureCapable() {
        #expect(TaisaEnvironment.production.allowsFixtures == false)
    }

    @Test func previewIsTheOnlyFixtureCapableEnvironment() {
        #expect(TaisaEnvironment.preview.allowsFixtures)
        #expect(TaisaEnvironment.development.allowsFixtures == false)
    }
}
