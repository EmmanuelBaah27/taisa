import Foundation

public protocol ConnectivityMonitoring: Sendable {
    func isAvailable() async -> Bool
}

public protocol ConnectivityObserving: ConnectivityMonitoring {
    func changes() async -> AsyncStream<Bool>
}

#if canImport(Network)
import Network

public actor SystemConnectivityMonitor: ConnectivityObserving {
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.taisa.voice.connectivity")
    private var available = false
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    public init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { await self?.update(path.status == .satisfied) }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }

    public func isAvailable() async -> Bool { available }

    public func changes() async -> AsyncStream<Bool> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            let current = available
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.remove(id) }
            }
        }
    }

    private func update(_ value: Bool) {
        available = value
        let current = Array(continuations.values)
        for continuation in current { continuation.yield(value) }
    }

    private func remove(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
#else
public struct SystemConnectivityMonitor: ConnectivityObserving {
    public init() {}
    public func isAvailable() async -> Bool { false }
    public func changes() async -> AsyncStream<Bool> { AsyncStream { $0.finish() } }
}
#endif
