public enum PreviewNetworkRequest: Sendable {
    case fixture
}

public enum PreviewTransportError: Error, Equatable, Sendable {
    case externalNetworkingDenied
}

public struct DeniedNetworkTransport: Sendable {
    public init() {}

    public func send(_ request: PreviewNetworkRequest) async throws {
        _ = request
        throw PreviewTransportError.externalNetworkingDenied
    }
}
