import SwiftUI

public struct TaisaSettingsNavigationRow: View {
    private let title: String
    private let icon: CentralIconName
    private let action: @MainActor () -> Void
    public init(_ title: String, icon: CentralIconName, action: @escaping @MainActor () -> Void) {
        self.title = title; self.icon = icon; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            HStack(spacing: TaisaSpacing.control.rawValue) {
                CentralIcon(icon)
                    .frame(width: TaisaControlMetric.standardIcon, height: TaisaControlMetric.standardIcon)
                    .foregroundStyle(TaisaColor.mutedForeground.color)
                TaisaText(role: .profileLabel, content: title)
                    .frame(minHeight: TaisaTypography.navigationLabel.lineHeight, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                CentralIcon(.profileChevron)
                    .frame(width: TaisaProfileMetric.chevron, height: TaisaProfileMetric.chevron)
                    .foregroundStyle(TaisaColor.mutedForeground.color)
            }
            .padding(.horizontal, TaisaSpacing.standard.rawValue)
            .padding(.vertical, TaisaSpacing.control.rawValue)
            .frame(minHeight: TaisaControlMetric.primaryNavigationItemHeight)
            .background(TaisaColor.subtleSurface.color)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint("Opens \(title)")
    }
}
