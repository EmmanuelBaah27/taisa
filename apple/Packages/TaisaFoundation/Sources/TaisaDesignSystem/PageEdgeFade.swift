import SwiftUI

public struct PageEdgeFade: View {
    public static let headerOpaqueStop = 0.40
    public static let navigationOpaqueStop = 0.40

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
                .init(color: .white.opacity(0.92), location: 0.50),
                .init(color: .white.opacity(0.72), location: 0.62),
                .init(color: .white.opacity(0.44), location: 0.76),
                .init(color: .white.opacity(0.18), location: 0.90),
                .init(color: .clear, location: 1),
            ]
        case .navigation:
            stops = [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: Self.navigationOpaqueStop),
                .init(color: .white.opacity(0.18), location: 0.50),
                .init(color: .white.opacity(0.44), location: 0.62),
                .init(color: .white.opacity(0.72), location: 0.76),
                .init(color: .white.opacity(0.92), location: 0.90),
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
