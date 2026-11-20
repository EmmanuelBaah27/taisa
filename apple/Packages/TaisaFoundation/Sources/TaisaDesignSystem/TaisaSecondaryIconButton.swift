import SwiftUI

/// The shared circular secondary action used in primary page headers.
public struct TaisaSecondaryIconButton: View {
    private let icon: CentralIconName
    private let accessibilityLabel: String
    private let accessibilityHint: String?
    private let iconColor: TaisaColor
    private let size: CGFloat
    private let elevation: TaisaSecondaryButtonElevation
    private let action: @MainActor () -> Void

    public init(
        icon: CentralIconName,
        accessibilityLabel: String,
        accessibilityHint: String? = nil,
        iconColor: TaisaColor = .foreground,
        size: CGFloat = TaisaControlMetric.headerActionHeight,
        elevation: TaisaSecondaryButtonElevation = .inline,
        action: @escaping @MainActor () -> Void
    ) {
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.iconColor = iconColor
        self.size = size
        self.elevation = elevation
        self.action = action
    }

    public var body: some View {
        secondaryGlassButton
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint ?? "")
    }

    @ViewBuilder private var secondaryGlassButton: some View {
        let button = Button(action: action) {
            CentralIcon(icon)
                .foregroundStyle(iconColor.color)
                .frame(width: TaisaControlMetric.standardIcon, height: TaisaControlMetric.standardIcon)
                .frame(width: size, height: size)
        }

        if #available(iOS 26.0, macOS 26.0, *) {
            button.buttonStyle(.plain)
                .glassEffect(.clear.interactive(), in: Circle())
                .modifier(TaisaSecondaryButtonSurface(shape: Circle(), elevation: elevation))
                .contentShape(Circle())
        } else {
            button.buttonStyle(.plain)
                .background(.regularMaterial, in: Circle())
                .modifier(TaisaSecondaryButtonSurface(shape: Circle(), elevation: elevation))
                .contentShape(Circle())
        }
    }
}
