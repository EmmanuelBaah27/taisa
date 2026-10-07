public protocol ConnectivityMonitoring: Sendable {
    func isAvailable() async -> Bool
}
