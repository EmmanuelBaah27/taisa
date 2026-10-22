import SwiftUI

public struct PageEdgeFade: View {
    public static let fadeStart = 0.40
    public static let headerOpaqueStop = 0.56
    public static let navigationOpaqueStop = 1 - fadeStart

    public enum Placement: Sendable {
        case header
        case navigation
    }

    private let placement: Placement

    public init(_ placement: Placement) {
        self.placement = placement
    }

    public var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(TaisaEffect.edgeFadeBlurOpacity)

            Rectangle()
                .fill(TaisaColor.background.color)
        }
        .mask(fadeMask)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var fadeMask: LinearGradient {
        let stops: [Gradient.Stop]
        switch placement {
        case .header:
            stops = [
                .init(color: .white, location: 0),
                .init(color: .white, location: Self.headerOpaqueStop),
                .init(color: .white.opacity(0.94), location: 0.64),
                .init(color: .white.opacity(0.76), location: 0.74),
                .init(color: .white.opacity(0.50), location: 0.84),
                .init(color: .white.opacity(0.24), location: 0.92),
                .init(color: .clear, location: 1),
            ]
        case .navigation:
            stops = [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(0.18), location: 0.10),
                .init(color: .white.opacity(0.44), location: 0.24),
                .init(color: .white.opacity(0.72), location: 0.38),
                .init(color: .white.opacity(0.92), location: 0.50),
                .init(color: .white, location: Self.navigationOpaqueStop),
                .init(color: .white, location: 1),
            ]
        }
        return LinearGradient(
            gradient: Gradient(stops: stops),
            startPoint: .top,
            endPoint: .bottom
        )
    }

}
