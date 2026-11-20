import SwiftUI

public enum TaisaSecondaryButtonElevation: Sendable, Equatable {
    case inline
    case floating
}

public typealias TaisaSecondaryButtonSize = TaisaButtonSize

extension TaisaButtonSize {
    var controlSize: ControlSize {
        self == .standard ? .regular : .small
    }
}

public enum TaisaSecondaryButtonContract {
    public static let borderColor = TaisaColor.border
    public static let floatingShadowOpacity = TaisaEffect.secondaryButtonShadowOpacity
    public static let floatingShadowRadius = TaisaEffect.secondaryButtonShadowRadius
}

private struct TaisaButtonSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let role: TaisaButtonRole
    let size: TaisaButtonSize
    let shape: TaisaButtonShape

    @ViewBuilder func body(content: Content) -> some View {
        let exactSurface = sized(content)
        let surfaceShape = resolvedShape
        if #available(iOS 26.0, macOS 26.0, *), !reduceTransparency {
            switch role {
            case .primary:
                exactSurface
                    .glassEffect(
                        .regular.tint(TaisaColor.primaryAction.color).interactive(),
                        in: surfaceShape
                    )
            case .secondary:
                exactSurface.glassEffect(.clear.interactive(), in: surfaceShape)
            case .ghost:
                exactSurface
            case .destructive:
                exactSurface.glassEffect(.regular.interactive(), in: surfaceShape)
            }
        } else if role == .primary {
            exactSurface.background(TaisaColor.primaryAction.color, in: surfaceShape)
        } else if role == .secondary || role == .ghost {
            exactSurface
        } else if reduceTransparency {
            exactSurface.background(TaisaColor.raisedSurface.color, in: surfaceShape)
        } else {
            exactSurface.background(.regularMaterial, in: surfaceShape)
        }
    }

    @ViewBuilder private func sized(_ content: Content) -> some View {
        switch shape {
        case .circle:
            content.frame(width: size.visualSize, height: size.visualSize)
        case .capsule, .roundedRectangle:
            content.frame(height: size.visualSize)
        }
    }

    private var resolvedShape: AnyShape {
        switch shape {
        case .circle: AnyShape(Circle())
        case .capsule: AnyShape(Capsule())
        case .roundedRectangle: AnyShape(RoundedRectangle(cornerRadius: TaisaRadius.control.rawValue))
        }
    }
}

public extension View {
    func taisaButtonSurface(
        role: TaisaButtonRole,
        size: TaisaButtonSize,
        shape: TaisaButtonShape
    ) -> some View {
        modifier(TaisaButtonSurfaceModifier(role: role, size: size, shape: shape))
    }
}
