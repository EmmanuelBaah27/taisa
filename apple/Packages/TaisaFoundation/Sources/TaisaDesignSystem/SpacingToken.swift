import CoreGraphics

public enum TaisaSpacing: CGFloat, CaseIterable, Sendable {
    case tight = 4
    case compact = 8
    case control = 12
    case standard = 16
    case content = 20
    case section = 24
    case page = 32
}

public enum TaisaMotion {
    /// Repeated page and primary-navigation feedback should feel immediate.
    public static let fast: Double = 0.18
}

public enum TaisaControlMetric {
    public static let standardIcon: CGFloat = 24
    public static let appBarHeight: CGFloat = 64
    public static let headerActionHeight: CGFloat = 48
    public static let primaryNavigationItemWidth: CGFloat = 56
    public static let primaryNavigationItemHeight: CGFloat = 48
    public static let recordingButtonWidth: CGFloat = 104
    public static let recordingButtonHeight: CGFloat = 48
    public static let chatPreviewLineHeight: CGFloat = 20
}

public enum TaisaEffect {
    public static let headerFadeOpacity: Double = 0.72
    public static let navigationFadeOpacity: Double = 0.72
    public static let edgeFadeBlurOpacity: Double = 0.42
    /// Figma's 20px blur maps to Core Graphics' 10pt blur radius.
    public static let recordingGlowBlurRadius: CGFloat = 10
    public static let recordingGlowSpread: CGFloat = 4
    public static let recordingGlowOpacity: Double = 0.35
}

public enum TaisaRadius: CGFloat, CaseIterable, Sendable {
    case control = 12
    case panel = 16
    case historyGroup = 20
    case composer = 24
    case circular = 9_999
}

public enum TaisaMaterial: Sendable, Equatable {
    case composer
    case dock

    public var reducedTransparencyFallback: TaisaColor { .raisedSurface }
}
