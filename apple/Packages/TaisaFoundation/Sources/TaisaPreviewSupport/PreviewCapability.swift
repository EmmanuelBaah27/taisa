import TaisaCore

public struct PreviewCapability: Sendable {
    public let environment: TaisaEnvironment

    public init(environment: TaisaEnvironment) {
        precondition(environment.allowsFixtures, "Preview capability requires the preview environment")
        self.environment = environment
    }
}
