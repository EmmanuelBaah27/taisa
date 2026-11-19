import SwiftUI

public enum TaisaGroupedIconActionRole: Sendable, Equatable {
    case neutral
    case destructive
}

public struct TaisaGroupedIconAction: Sendable {
    public let icon: CentralIconName
    public let role: TaisaGroupedIconActionRole
    public let accessibilityLabel: String
    public let action: @MainActor @Sendable () -> Void

    public init(
        icon: CentralIconName,
        role: TaisaGroupedIconActionRole = .neutral,
        accessibilityLabel: String,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        self.icon = icon
        self.role = role
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }
}

public enum TaisaGroupedIconActionsContract {
    public static let actionCount = 2
    public static let iconSize: CGFloat = TaisaControlMetric.standardIcon
    public static let minimumHitSize: CGFloat = TaisaControlMetric.headerActionHeight
    public static let usesSharedCapsuleSurface = true
}

public struct TaisaGroupedIconActions: View {
    private let actions: [TaisaGroupedIconAction]

    public init(_ actions: [TaisaGroupedIconAction]) {
        precondition(actions.count == TaisaGroupedIconActionsContract.actionCount)
        self.actions = actions
    }

    public var body: some View {
        HStack(spacing: TaisaControlMetric.groupedActionGap) {
            ForEach(Array(actions.enumerated()), id: \.offset) { _, item in
                TaisaPressable(action: item.action) {
                    CentralIcon(item.icon)
                        .foregroundStyle(iconColor(for: item.role))
                        .frame(
                            width: TaisaGroupedIconActionsContract.iconSize,
                            height: TaisaGroupedIconActionsContract.iconSize
                        )
                        .frame(
                            minWidth: TaisaGroupedIconActionsContract.minimumHitSize,
                            minHeight: TaisaGroupedIconActionsContract.minimumHitSize
                        )
                }
                .accessibilityLabel(item.accessibilityLabel)
            }
        }
        .padding(.horizontal, TaisaControlMetric.groupedActionHorizontalInset)
        .background(TaisaColor.background.color, in: Capsule())
        .overlay { Capsule().stroke(TaisaColor.border.color) }
        .shadow(
            color: TaisaColor.foreground.color.opacity(TaisaEffect.groupedActionShadowOpacity),
            radius: TaisaEffect.groupedActionShadowRadius,
            y: TaisaEffect.groupedActionShadowY
        )
    }

    private func iconColor(for role: TaisaGroupedIconActionRole) -> Color {
        role == .destructive ? TaisaColor.destructive.color : TaisaColor.foreground.color
    }
}
