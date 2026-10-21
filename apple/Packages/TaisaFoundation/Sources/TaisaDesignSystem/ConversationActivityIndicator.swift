import SwiftUI

public struct ConversationActivityIndicator: View {
    public static let animationDuration: Double = TaisaMotion.activityCycle
    public enum Motion: Sendable, Equatable { case animated, staticFrame
        public static let reduced: Self = .staticFrame
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let active: Bool
    @State private var animate = false

    public init(active: Bool) { self.active = active }

    public var body: some View {
        HStack(spacing: TaisaActivityIndicatorMetric.barSpacing) {
            bar(TaisaColor.primaryAction.color, delay: 0)
            bar(TaisaColor.activityWarmAccent, delay: TaisaMotion.activityStagger)
            bar(TaisaColor.activityCoolAccent, delay: TaisaMotion.activityStagger * 2)
        }
        .frame(width: TaisaActivityIndicatorMetric.width, height: TaisaActivityIndicatorMetric.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(active ? "Recording in progress" : "Recording paused")
        .onAppear { updateMotion() }
        .onChange(of: active) { _, _ in updateMotion() }
        .onChange(of: reduceMotion) { _, _ in updateMotion() }
    }

    private func bar(_ color: Color, delay: Double) -> some View {
        RoundedRectangle(cornerRadius: TaisaActivityIndicatorMetric.barRadius)
            .fill(color)
            .frame(
                width: TaisaActivityIndicatorMetric.barWidth,
                height: animate ? TaisaActivityIndicatorMetric.activeBarHeight : TaisaActivityIndicatorMetric.restingBarHeight
            )
            .animation(TaisaMotion.activityAnimation.delay(delay), value: animate)
    }

    private func updateMotion() { animate = active && !reduceMotion }
}
