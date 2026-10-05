public enum TaisaError: Error, Equatable, Sendable {
    case unavailable
    case invalidConfiguration(String)
}
