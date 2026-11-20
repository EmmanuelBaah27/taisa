import SwiftUI

/// The shared capsule secondary action used in primary page headers.
public struct TaisaSecondaryCapsuleButton<Label: View>: View {
    private let action: @MainActor () -> Void
    private let label: Label
    private let size: TaisaSecondaryButtonSize
    private let elevation: TaisaSecondaryButtonElevation

    public init(
        size: TaisaSecondaryButtonSize = .standard,
        elevation: TaisaSecondaryButtonElevation = .inline,
        action: @escaping @MainActor () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.elevation = elevation
        self.size = size
        self.action = action
        self.label = label()
    }

    public var body: some View { secondaryGlassButton }

    private var secondaryGlassButton: some View {
        TaisaButtonControl(
            style: TaisaButtonStyle(
                role: .ghost,
                size: size
            ),
            action: action
        ) {
            label.padding(.horizontal, TaisaSpacing.standard.rawValue)
        }
        .contentShape(.interaction, Capsule().inset(by: -size.hitSlop))
    }
}
