import SwiftUI

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
    /// Longer on-screen movement should remain legible instead of snapping across distance.
    public static let settle: Double = 0.50
    /// Cadence between provisional words resolving into a streamed response.
    public static let streamingWordGap: Double = 0.06
    /// Duration of each provisional word's soft resolution.
    public static let streamingWordFade: Double = 0.35
    /// Semantic ease for provisional streamed words resolving into their final form.
    public static let streamingWordRevealCurve = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.22, y: 1),
        endControlPoint: UnitPoint(x: 0.36, y: 1)
    )
}

public enum TaisaControlMetric {
    public static let conversationComposerDockHeight: CGFloat = 96
    public static let standardIcon: CGFloat = 24
    public static let appBarHeight: CGFloat = 64
    public static let headerActionHeight: CGFloat = 44
    public static let childNavigationControlHeight: CGFloat = 48
    public static let primaryNavigationItemWidth: CGFloat = 56
    public static let primaryNavigationItemHeight: CGFloat = 48
    public static let recordingButtonWidth: CGFloat = 104
    public static let recordingButtonHeight: CGFloat = 48
    public static let primaryNavigationReservedHeight: CGFloat = 152
    public static let chatPreviewLineHeight: CGFloat = 20
    public static let conversationTitleWidth: CGFloat = 220
    public static let conversationRecordingControl: CGFloat = 48
    public static let conversationActionSpacing: CGFloat = 12
    public static let toastMinimumHeight: CGFloat = 44
    public static let contextMenuIcon: CGFloat = 16
    public static let conversationEmptyVoiceIcon: CGFloat = 24
    public static let messageEditorMinimumHeight: CGFloat = 120
    public static let disabledControlOpacity: CGFloat = 0.38
}

public enum TaisaEffect {
    public static let edgeFadeBlurOpacity: Double = 0.42
    /// Figma's 20px blur maps to Core Graphics' 10pt blur radius.
    public static let recordingGlowBlurRadius: CGFloat = 10
    public static let recordingGlowSpread: CGFloat = 4
    public static let recordingGlowOpacity: Double = 0.35
    public static let streamingWordBlurRadius: CGFloat = 1
    public static let placeholderHighlightOpacity: Double = 0.72
    public static let placeholderHighlightWidthFraction: CGFloat = 0.55
    public static let placeholderTravelStart: CGFloat = -1
    public static let placeholderTravelEnd: CGFloat = 1.5
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
