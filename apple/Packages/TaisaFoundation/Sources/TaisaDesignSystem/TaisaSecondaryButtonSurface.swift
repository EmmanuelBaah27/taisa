import SwiftUI

public enum TaisaSecondaryButtonElevation: Sendable, Equatable {
    case inline
    case floating
}

public enum TaisaSecondaryButtonContract {
    public static let borderColor = TaisaColor.border
    public static let floatingShadowOpacity = TaisaEffect.secondaryButtonShadowOpacity
    public static let floatingShadowRadius = TaisaEffect.secondaryButtonShadowRadius
}

struct TaisaSecondaryButtonSurface<Surface: Shape>: ViewModifier {
    let shape: Surface
    let elevation: TaisaSecondaryButtonElevation

    func body(content: Content) -> some View {
        content
            .overlay { shape.stroke(TaisaSecondaryButtonContract.borderColor.color) }
            .shadow(
                color: TaisaColor.foreground.color.opacity(
                    elevation == .floating ? TaisaSecondaryButtonContract.floatingShadowOpacity : 0
                ),
                radius: elevation == .floating ? TaisaSecondaryButtonContract.floatingShadowRadius : 0,
                y: elevation == .floating ? TaisaEffect.secondaryButtonShadowY : 0
            )
    }
}
