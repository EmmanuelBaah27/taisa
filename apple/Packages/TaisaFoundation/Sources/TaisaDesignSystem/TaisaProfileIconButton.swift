import SwiftUI

public struct TaisaProfileIconButton: View {
    private let icon: CentralIconName
    private let label: String
    private let action: @MainActor () -> Void
    public init(icon: CentralIconName, label: String, action: @escaping @MainActor () -> Void) {
        self.icon = icon; self.label = label; self.action = action
    }
    public var body: some View {
        TaisaSecondaryIconButton(
            icon: icon,
            accessibilityLabel: label,
            iconColor: .foreground,
            size: .standard,
            action: action
        )
    }
}
