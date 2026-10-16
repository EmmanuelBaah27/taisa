import SwiftUI

public struct TaisaToast: View {
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var dragOffset: CGFloat = 0

    private let message: String
    private let actionLabel: String?
    private let action: (@MainActor () -> Void)?
    private let dismiss: @MainActor () -> Void
    private let contract: Contract

    public init(
        message: String,
        actionLabel: String? = nil,
        contract: Contract = .default,
        action: (@MainActor () -> Void)? = nil,
        dismiss: @escaping @MainActor () -> Void
    ) {
        self.message = message
        self.actionLabel = actionLabel
        self.contract = contract
        self.action = action
        self.dismiss = dismiss
    }

    public var body: some View {
        HStack(spacing: TaisaSpacing.control.rawValue) {
            Text(message)
                .font(TaisaTypography.navigationLabel.font)
                .foregroundStyle(TaisaColor.foreground.color)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .font(TaisaTypography.navigationLabel.font)
                    .foregroundStyle(TaisaColor.foreground.color)
                    .frame(minHeight: 44)
                    .padding(.horizontal, TaisaSpacing.compact.rawValue)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, TaisaSpacing.standard.rawValue)
        .frame(minHeight: TaisaControlMetric.toastMinimumHeight)
        .background {
            if reduceTransparency {
                Capsule().fill(TaisaColor.raisedSurface.color)
            } else {
                Capsule().fill(.regularMaterial)
            }
        }
        .overlay { Capsule().stroke(TaisaColor.border.color) }
        .shadow(color: TaisaColor.foreground.color.opacity(0.06), radius: TaisaSpacing.control.rawValue)
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
