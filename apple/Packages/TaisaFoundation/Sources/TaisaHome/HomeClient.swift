import TaisaStorage

public struct HomeClient: Sendable {
    public var load: @Sendable () async throws -> HomeSnapshot

    public init(load: @escaping @Sendable () async throws -> HomeSnapshot) {
        self.load = load
    }
}
