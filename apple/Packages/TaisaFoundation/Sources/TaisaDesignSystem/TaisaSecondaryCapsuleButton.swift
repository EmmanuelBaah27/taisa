import SwiftUI

/// The shared capsule secondary action used in primary page headers.
public struct TaisaSecondaryCapsuleButton<Label: View>: View {
    private let action: @MainActor () -> Void
    private let label: Label
    private let height: CGFloat
    private let elevation: TaisaSecondaryButtonElevation

    public init(
        height: CGFloat = TaisaControlMetric.headerActionHeight,
        elevation: TaisaSecondaryButtonElevation = .inline,
        action: @escaping @MainActor () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.height = height
        self.elevation = elevation
        self.action = action
        self.label = label()
    }

    public var body: some View { secondaryGlassButton }

    @ViewBuilder private var secondaryGlassButton: some View {
        let button = Button(action: action) { label.frame(height: height) }
        if #available(iOS 26.0, macOS 26.0, *) {
            button.buttonStyle(.plain)
                .glassEffect(.clear.interactive(), in: Capsule())
                .modifier(TaisaSecondaryButtonSurface(shape: Capsule(), elevation: elevation))
                .contentShape(Capsule())
        } else {
            button.buttonStyle(.plain)
                .background(.regularMaterial, in: Capsule())
                .modifier(TaisaSecondaryButtonSurface(shape: Capsule(), elevation: elevation))
                .contentShape(Capsule())
        }
    }
}
