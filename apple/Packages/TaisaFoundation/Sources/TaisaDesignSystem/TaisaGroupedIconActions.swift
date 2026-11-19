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
    public static let controlHeight: CGFloat = TaisaControlMetric.headerActionHeight
    public static let usesSharedSecondaryIconButtons = true
}

public struct TaisaGroupedIconActions: View {
    private let actions: [TaisaGroupedIconAction]
    private let elevation: TaisaSecondaryButtonElevation

    public init(
        _ actions: [TaisaGroupedIconAction],
        elevation: TaisaSecondaryButtonElevation = .inline
    ) {
        precondition(actions.count == TaisaGroupedIconActionsContract.actionCount)
        self.actions = actions
        self.elevation = elevation
    }

    public var body: some View {
        HStack(spacing: TaisaControlMetric.groupedActionGap) {
            ForEach(Array(actions.enumerated()), id: \.offset) { _, item in
                TaisaSecondaryIconButton(
                    icon: item.icon,
                    accessibilityLabel: item.accessibilityLabel,
                    iconColor: iconColor(for: item.role),
                    size: TaisaGroupedIconActionsContract.controlHeight,
                    elevation: elevation,
                    action: item.action
                )
            }
        }
    }

    private func iconColor(for role: TaisaGroupedIconActionRole) -> TaisaColor {
        role == .destructive ? .destructive : .foreground
    }
}
