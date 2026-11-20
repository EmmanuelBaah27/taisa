import SwiftUI

/// The shared capsule secondary action used in primary page headers.
public struct TaisaSecondaryCapsuleButton<Label: View>: View {
    private let action: @MainActor () -> Void
    private let label: Label

    public init(
        elevation: TaisaSecondaryButtonElevation = .inline,
        action: @escaping @MainActor () -> Void,
        @ViewBuilder label: () -> Label
    ) {
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
        .frame(minHeight: TaisaControlMetric.headerActionHeight)
    }
}
