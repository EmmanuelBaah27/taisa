import SwiftUI

/// A full-screen scrim that dismisses only from a tap that begins on the scrim.
public struct TaisaDismissBackdrop: View {
    private let action: @MainActor () -> Void

    public init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    public var body: some View {
        TaisaColor.foreground.color
            .opacity(TaisaEffect.taskComposerBackdropOpacity)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { _ in action() })
            .accessibilityHidden(true)
    }
}
