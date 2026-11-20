import SwiftUI

/// Business-free activation primitive for reusable row and card labels.
///
/// Product owns the action and label meaning. The design system owns native
/// activation, the minimum touch target, and the absence of feature-local
/// button styling.
public struct TaisaPressable<Label: View>: View {
    private let action: @MainActor () -> Void
    private let label: Label

    public init(
        action: @escaping @MainActor () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.action = action
        self.label = label()
    }

    public var body: some View {
        TaisaButtonControl(style: TaisaButtonStyle(presentation: .content), action: action) { label }
            .frame(minHeight: TaisaControlMetric.headerActionHeight)
            .contentShape(Rectangle())
    }
}
