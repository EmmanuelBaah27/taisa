import SwiftUI

/// The shared capsule secondary action used in primary page headers.
public struct TaisaSecondaryCapsuleButton<Label: View>: View {
    private let action: @MainActor () -> Void
    private let label: Label
    private let height: CGFloat

    public init(
        height: CGFloat = TaisaControlMetric.headerActionHeight,
        elevation: TaisaSecondaryButtonElevation = .inline,
        action: @escaping @MainActor () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.height = height
        // Elevation is system-owned by the shared native style.
        _ = elevation
        self.action = action
        self.label = label()
    }

    public var body: some View { secondaryGlassButton }

    private var secondaryGlassButton: some View {
        TaisaButtonControl(style: TaisaButtonStyle(), action: action) {
            label
        }
        .frame(minHeight: height)
    }
}
