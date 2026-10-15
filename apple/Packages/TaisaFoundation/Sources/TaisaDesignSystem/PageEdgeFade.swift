import SwiftUI

public struct PageEdgeFade: View {
    public static let headerOpaqueStop = 0.70
    public static let navigationOpaqueStop = 0.54565

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

            LinearGradient(
                gradient: placement == .header ? headerGradient : navigationGradient,
                startPoint: .top,
                endPoint: .bottom
            )
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
                .init(color: .clear, location: 1),
            ]
        case .navigation:
            stops = [
                .init(color: .clear, location: 0),
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

    private var headerGradient: Gradient {
        Gradient(stops: [
            .init(color: TaisaColor.background.color, location: 0),
            .init(color: TaisaColor.background.color, location: Self.headerOpaqueStop),
            .init(color: TaisaColor.background.color.opacity(0), location: 1),
        ])
    }

    private var navigationGradient: Gradient {
        Gradient(stops: [
            .init(color: TaisaColor.background.color.opacity(0), location: 0),
            .init(color: TaisaColor.background.color, location: Self.navigationOpaqueStop),
            .init(color: TaisaColor.background.color, location: 1),
        ])
    }
}
