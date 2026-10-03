import Testing
@testable import TaisaCore

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
