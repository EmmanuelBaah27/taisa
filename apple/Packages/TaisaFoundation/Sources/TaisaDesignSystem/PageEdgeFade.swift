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
        LinearGradient(
            gradient: placement == .header ? headerGradient : navigationGradient,
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
