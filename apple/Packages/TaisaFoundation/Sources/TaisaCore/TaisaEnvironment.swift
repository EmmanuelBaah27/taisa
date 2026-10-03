public enum TaisaEnvironment: String, Codable, Sendable {
    case development
    case preview
    case production

    public init(configurationValue: String) throws {
        guard let environment = Self(rawValue: configurationValue) else {
            throw TaisaEnvironmentError.unknownConfiguration(configurationValue)
        }
        self = environment
    }

    public var allowsFixtures: Bool {
        self == .preview
    }
}

public enum TaisaEnvironmentError: Error, Equatable, Sendable {
    case unknownConfiguration(String)
}
