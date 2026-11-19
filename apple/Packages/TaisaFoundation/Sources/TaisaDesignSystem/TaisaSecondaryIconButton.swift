import SwiftUI

/// The shared circular secondary action used in primary page headers.
public struct TaisaSecondaryIconButton: View {
    private let icon: CentralIconName
    private let accessibilityLabel: String
    private let accessibilityHint: String?
    private let size: CGFloat
    private let action: @MainActor () -> Void

    public init(
        icon: CentralIconName,
        accessibilityLabel: String,
        accessibilityHint: String? = nil,
        size: CGFloat = TaisaControlMetric.headerActionHeight,
        action: @escaping @MainActor () -> Void
    ) {
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.size = size
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
                .frame(
                    width: TaisaControlMetric.standardIcon,
                    height: TaisaControlMetric.standardIcon
                )
                .frame(
                    width: size,
                    height: size
                )
        }

        if #available(iOS 26.0, macOS 26.0, *) {
            button
                .buttonStyle(.plain)
                .glassEffect(.clear.interactive(), in: Circle())
                .contentShape(Circle())
        } else {
            button
                .buttonStyle(.plain)
                .background(.regularMaterial, in: Circle())
                .contentShape(Circle())
        }
    }
}
