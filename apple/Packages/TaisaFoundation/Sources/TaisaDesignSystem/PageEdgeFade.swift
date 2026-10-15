import SwiftUI

public struct PageEdgeFade: View {
    public enum Placement: Sendable {
        case header
        case navigation
    }

    private let placement: Placement

    public init(_ placement: Placement) {
        self.placement = placement
    }

    public var body: some View {
        LinearGradient(
            colors: placement == .header
                ? [TaisaColor.background.color, TaisaColor.background.color.opacity(0)]
                : [TaisaColor.background.color.opacity(0), TaisaColor.background.color],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
