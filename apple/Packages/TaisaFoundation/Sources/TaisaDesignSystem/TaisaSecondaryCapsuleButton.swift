import SwiftUI

/// The shared capsule secondary action used in primary page headers.
public struct TaisaSecondaryCapsuleButton<Label: View>: View {
    private let action: @MainActor () -> Void
    private let label: Label
    private let height: CGFloat

    public init(
        height: CGFloat = TaisaControlMetric.headerActionHeight,
        action: @escaping @MainActor () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.height = height
        self.action = action
        self.label = label()
    }

    public var body: some View {
        secondaryGlassButton
    }

    private var secondaryGlassButton: some View {
        TaisaButtonControl(style: TaisaButtonStyle(), action: action) {
            label
                .frame(height: height)
        }
    }
}
