import SwiftUI

public struct ConversationActivityIndicator: View {
    public static let animationDuration: Double = 2
    public enum Motion: Sendable, Equatable { case animated, staticFrame
        public static let reduced: Self = .staticFrame
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let active: Bool
    @State private var animate = false

    public init(active: Bool) { self.active = active }

    public var body: some View {
        HStack(spacing: 2) {
            bar(TaisaColor.primaryAction.color, delay: 0)
            bar(Color.orange.opacity(0.65), delay: 0.18)
            bar(Color.purple.opacity(0.55), delay: 0.36)
        }
        .frame(width: 44, height: 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(active ? "Recording in progress" : "Recording paused")
        .onAppear { updateMotion() }
        .onChange(of: active) { _, _ in updateMotion() }
        .onChange(of: reduceMotion) { _, _ in updateMotion() }
    }

    private func bar(_ color: Color, delay: Double) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: 12, height: animate ? 22 : 10)
            .animation(.easeInOut(duration: Self.animationDuration / 2).repeatForever(autoreverses: true).delay(delay), value: animate)
    }

    private func updateMotion() { animate = active && !reduceMotion }
}
