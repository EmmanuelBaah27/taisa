public enum TaisaImmersivePresentationPhase: Sendable, Equatable {
    case active
    case committing
    case dismissed

    public var keepsContentVisible: Bool { self != .dismissed }
    public var allowsCloseRequest: Bool { self == .active }
}

@MainActor
public final class TaisaSystemTransferPolicy {
    public private(set) var result: TaisaPresentationResult?

    public init() {}

    public func complete(with result: TaisaPresentationResult) -> Bool {
        guard self.result == nil else { return false }
        self.result = result
        return true
    }
}
