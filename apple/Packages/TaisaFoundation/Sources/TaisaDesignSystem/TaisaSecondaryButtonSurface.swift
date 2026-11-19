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

// Button depth and border rendering belong to TaisaButtonStyle.
