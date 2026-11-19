import SwiftUI

public struct TaisaProfileIconButton: View {
    private let icon: CentralIconName
    private let label: String
    private let action: @MainActor () -> Void
    public init(icon: CentralIconName, label: String, action: @escaping @MainActor () -> Void) {
        self.icon = icon; self.label = label; self.action = action
    }
    public var body: some View {
        TaisaButtonControl(style: TaisaButtonStyle(shape: .circle), action: action) {
            CentralIcon(icon)
                .frame(width: TaisaControlMetric.standardIcon, height: TaisaControlMetric.standardIcon)
                .foregroundStyle(TaisaColor.mutedForeground.color)
                .frame(minWidth: TaisaControlMetric.headerActionHeight, minHeight: TaisaControlMetric.headerActionHeight)
        }
        .accessibilityLabel(label)
    }
}
