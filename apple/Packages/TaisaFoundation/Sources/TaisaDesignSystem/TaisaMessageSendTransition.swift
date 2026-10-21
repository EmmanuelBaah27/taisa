import SwiftUI

public struct TaisaMessageSendTransition: ViewModifier {
    public enum Contract {
        /// The frequent composer-to-bubble morph should acknowledge the send
        /// without making the user watch content cross the whole viewport.
        public static let duration = TaisaMotion.fast
        /// Position-only interpolation keeps the handoff stable while the
        /// keyboard, composer chrome, and timeline are relaying out together.
        public static let stabilizesConcurrentLayoutChanges = true
    }

    public enum Role: Sendable, Equatable {
        case composer
        case message
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let isActive: Bool
    private let namespace: Namespace.ID
    private let role: Role

    public init(isActive: Bool, namespace: Namespace.ID, role: Role) {
        self.isActive = isActive
        self.namespace = namespace
        self.role = role
    }

    @ViewBuilder public func body(content: Content) -> some View {
        if isActive, !reduceMotion {
            content.matchedGeometryEffect(
                id: "taisa.message-send",
                in: namespace,
                properties: .position,
                anchor: .center,
                isSource: role == .composer
            )
            .opacity(role == .message ? 0 : 1)
        } else if isActive {
            content.opacity(role == .message ? 0 : 1)
        } else {
            content
        }
    }
}

public extension View {
    func taisaMessageSendTransition(
        isActive: Bool,
        namespace: Namespace.ID,
        role: TaisaMessageSendTransition.Role
    ) -> some View {
        modifier(TaisaMessageSendTransition(isActive: isActive, namespace: namespace, role: role))
    }
}
