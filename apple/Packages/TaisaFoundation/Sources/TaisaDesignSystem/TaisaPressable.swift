import SwiftUI

/// Business-free activation primitive for reusable row and card labels.
///
/// Product owns the action and label meaning. The design system owns native
/// activation, the minimum touch target, and the absence of feature-local
/// button styling.
public struct TaisaPressable<Label: View>: View {
    private let role: ButtonRole?
    private let action: @MainActor () -> Void
    private let label: Label

    public init(
        role: ButtonRole? = nil,
        action: @escaping @MainActor () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.role = role
        self.action = action
        self.label = label()
    }

    public var body: some View {
        TaisaButtonControl(role: role, style: TaisaButtonStyle(presentation: .content), action: action) { label }
            .frame(minHeight: TaisaControlMetric.headerActionHeight)
            .contentShape(Rectangle())
    }
}
