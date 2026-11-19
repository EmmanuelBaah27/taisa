import SwiftUI

public struct TaisaToolbarAction: View {
    private let label: String
    private let icon: CentralIconName
    private let action: @MainActor () -> Void

    public init(label: String, icon: CentralIconName, action: @escaping @MainActor () -> Void) {
        self.label = label
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(action: action) { CentralIcon(icon).frame(width: 24, height: 24) }
            .buttonStyle(.plain)
            .frame(minWidth: TaisaControlMetric.headerActionHeight, minHeight: TaisaControlMetric.headerActionHeight)
            .accessibilityLabel(label)
    }
}
