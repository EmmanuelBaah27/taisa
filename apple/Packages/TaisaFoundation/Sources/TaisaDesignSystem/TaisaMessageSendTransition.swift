import SwiftUI

public struct TaisaMessageSendTransition: ViewModifier {
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
                properties: .frame,
                anchor: .center,
                isSource: role == .composer
            )
        } else if isActive {
            content.transition(.opacity)
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
