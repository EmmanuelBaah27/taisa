import SwiftUI
import Testing
@testable import TaisaPreviewSupport

@Suite("Preview registry")
@MainActor
struct PreviewRegistryTests {
    @Test func registryRejectsDuplicateIdentifiers() {
        let fixture = PreviewScenario(
            identifier: "foundation.default",
            title: "Foundation default",
            deviceFamily: .adaptive,
            accessibility: .default,
            readiness: .ready
        ) {
            AnyView(Text("Synthetic preview"))
        }

        #expect(throws: PreviewRegistryError.duplicateIdentifier("foundation.default")) {
            try PreviewRegistry(scenarios: [fixture, fixture])
        }
    }

    @Test func registryFindsScenarioByStableIdentifier() throws {
        let fixture = PreviewScenario(
            identifier: "foundation.default",
            title: "Foundation default",
            deviceFamily: .adaptive,
            accessibility: .default,
            readiness: .ready
        ) {
            AnyView(Text("Synthetic preview"))
        }

        let registry = try PreviewRegistry(scenarios: [fixture])
        #expect(registry.scenario(identifier: "foundation.default")?.title == "Foundation default")
    }
}
