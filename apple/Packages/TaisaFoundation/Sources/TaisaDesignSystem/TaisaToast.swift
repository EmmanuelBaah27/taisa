import SwiftUI

public struct TaisaToast: View {
    public enum Style: Sendable, Equatable { case dark, light }
    public enum Placement: Sendable, Equatable { case top }
    public enum SwipeDirection: Sendable, Equatable { case up }

    public struct Contract: Sendable, Equatable {
        public let placement: Placement
        public let dismissAfter: TimeInterval
        public let swipeDirection: SwipeDirection
        public let announcesWithVoiceOver: Bool

        public static let `default` = Contract(
            placement: .top,
            dismissAfter: 4,
            swipeDirection: .up,
            announcesWithVoiceOver: true
        )
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0

    private let message: String
    private let actionLabel: String?
    private let action: (@MainActor () -> Void)?
    private let dismiss: @MainActor () -> Void
    private let contract: Contract
    private let style: Style

    public init(
        message: String,
        actionLabel: String? = nil,
        contract: Contract = .default,
        style: Style = .dark,
        action: (@MainActor () -> Void)? = nil,
        dismiss: @escaping @MainActor () -> Void
    ) {
        self.message = message
        self.actionLabel = actionLabel
        self.contract = contract
        self.style = style
        self.action = action
        self.dismiss = dismiss
    }

    public var body: some View {
        HStack(spacing: TaisaSpacing.control.rawValue) {
            if style == .light {
                CentralIcon(.completed)
                    .frame(width: TaisaControlMetric.compactActionIcon, height: TaisaControlMetric.compactActionIcon)
            }
            Text(message)
                .font(TaisaTypography.navigationLabel.font)
                .foregroundStyle(style == .light ? TaisaColor.foreground.color : TaisaColor.background.color)
                .lineLimit(1)

            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .font(TaisaTypography.navigationLabel.font)
                    .foregroundStyle(style == .light ? TaisaColor.foreground.color : TaisaColor.background.color)
                    .frame(minHeight: TaisaControlMetric.toastMinimumHeight)
                    .padding(.horizontal, TaisaSpacing.compact.rawValue)
                    .buttonStyle(.plain)
                    .layoutPriority(1)
            }
        }
        .padding(.horizontal, TaisaSpacing.control.rawValue)
        .frame(minHeight: TaisaControlMetric.toastMinimumHeight)
        .background(style == .light ? TaisaColor.background.color : TaisaColor.foreground.color, in: RoundedRectangle(cornerRadius: style == .light ? TaisaRadius.taskToast : TaisaRadius.circular.rawValue))
        .shadow(
            color: TaisaColor.foreground.color.opacity(TaisaEffect.taskToastShadowOpacity),
            radius: TaisaEffect.taskToastShadowRadius,
            x: TaisaEffect.taskToastShadowX,
            y: TaisaEffect.taskToastShadowY
        )
        .offset(y: min(0, dragOffset))
        .contentShape(Capsule())
        .gesture(
            DragGesture()
                .onChanged { value in dragOffset = min(0, value.translation.height) }
                .onEnded { value in
                    if value.translation.height <= -TaisaSpacing.section.rawValue {
                        dismiss()
                    } else {
                        withAnimation(reduceMotion ? nil : .snappy(duration: TaisaMotion.fast)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .accessibilityElement(children: .contain)
        .onAppear { AccessibilityNotification.Announcement(message).post() }
        .task(id: message) {
            try? await Task.sleep(for: .seconds(contract.dismissAfter))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }
}
