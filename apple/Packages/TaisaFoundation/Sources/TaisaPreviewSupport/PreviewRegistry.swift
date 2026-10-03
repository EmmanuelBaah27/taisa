public enum PreviewRegistryError: Error, Equatable, Sendable {
    case duplicateIdentifier(String)
}

public struct PreviewRegistry: Sendable {
    public let scenarios: [PreviewScenario]
    private let scenariosByIdentifier: [String: PreviewScenario]

    public init(scenarios: [PreviewScenario]) throws {
        var indexed: [String: PreviewScenario] = [:]
        for scenario in scenarios {
            guard indexed[scenario.identifier] == nil else {
                throw PreviewRegistryError.duplicateIdentifier(scenario.identifier)
            }
            indexed[scenario.identifier] = scenario
        }
        self.scenarios = scenarios
        scenariosByIdentifier = indexed
    }

    public func scenario(identifier: String) -> PreviewScenario? {
        scenariosByIdentifier[identifier]
    }
}
