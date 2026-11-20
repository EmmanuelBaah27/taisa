import SwiftUI

/// The shared circular secondary action used in primary page headers.
public struct TaisaSecondaryIconButton: View {
    private let icon: CentralIconName
    private let accessibilityLabel: String
    private let accessibilityHint: String?
    private let iconColor: TaisaColor
    private let size: TaisaSecondaryButtonSize
    private let action: @MainActor () -> Void

    public init(
        icon: CentralIconName,
        accessibilityLabel: String,
        accessibilityHint: String? = nil,
        iconColor: TaisaColor = .foreground,
        size: TaisaSecondaryButtonSize = .standard,
        elevation: TaisaSecondaryButtonElevation = .inline,
        action: @escaping @MainActor () -> Void
    ) {
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.iconColor = iconColor
        self.size = size
        // Elevation is system-owned by the shared native style.
        _ = elevation
        self.action = action
    }

    public var body: some View {
        secondaryGlassButton
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint ?? "")
    }

    private var secondaryGlassButton: some View {
        TaisaButtonControl(
            style: TaisaButtonStyle(shape: .circle, size: size),
            action: action
        ) {
            CentralIcon(icon)
                .foregroundStyle(iconColor.color)
                .frame(width: TaisaControlMetric.standardIcon, height: TaisaControlMetric.standardIcon)
        }
        .contentShape(.interaction, Circle().inset(by: -size.hitSlop))
    }
}
