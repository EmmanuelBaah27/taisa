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
    /// App-wide overlays enter and exit quickly enough to preserve direct manipulation.
    public static let overlayEaseOutDuration: Double = fast
    /// Strong ease-out for app-wide overlays entering from or returning to an edge.
    public static var overlayEaseOut: Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: overlayEaseOutDuration)
    }
    /// Longer on-screen movement should remain legible instead of snapping across distance.
    public static let settle: Double = 0.50
    /// Recorder controls recede slightly as one group when a discard is confirmed.
    public static let recordingControlExitScale: CGFloat = 0.95
    /// Cadence between provisional words resolving into a streamed response.
    public static let streamingWordGap: Double = 0.06
    /// Duration of each provisional word's soft resolution.
    public static let streamingWordFade: Double = 0.35
    /// Continuous auto-follow must settle more gently than a discrete control response.
    public static let streamingScrollFollow: Double = 0.35
    /// Semantic ease for provisional streamed words resolving into their final form.
    public static let streamingWordRevealCurve = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.22, y: 1),
        endControlPoint: UnitPoint(x: 0.36, y: 1)
    )
}

public enum TaisaProfileMetric {
    public static let avatar: CGFloat = TaisaSecondaryButtonSize.standard.visualSize
    public static let editorAvatar: CGFloat = 56
    public static let chevron: CGFloat = 20
    public static let rowGap: CGFloat = 2
    public static let headerGap: CGFloat = 2
    public static let nameSize: CGFloat = 28
    public static let nameLineHeight: CGFloat = 36
}

public enum TaisaControlMetric {
    public static let taskHeaderHeight: CGFloat = 82
    public static let taskComposerHeight: CGFloat = 124
    public static let taskComposerCardHeight: CGFloat = 100
    public static let taskControl: CGFloat = 40
    public static let taskDueIcon: CGFloat = 16
    public static let actionButtonHeight: CGFloat = 48
    public static let compactActionButtonHeight: CGFloat = 36
    public static let compactActionIcon: CGFloat = 20
    /// The canonical canvas height used by both the recording glow lab and product surface.
    public static let recordingGlowSurfaceHeight: CGFloat = 240
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
    public static let groupedActionGap: CGFloat = 6
    public static let groupedActionHorizontalInset: CGFloat = 4
}

public enum TaisaEffect {
    public static let taskComposerShadowOpacity: Double = 0.08
    public static let taskComposerBackdropOpacity: Double = 0.30
    public static let taskComposerShadowRadius: CGFloat = 10
    public static let taskToastShadowOpacity: Double = 0.16
    public static let taskToastShadowRadius: CGFloat = 8
    public static let taskToastShadowX: CGFloat = 3
    public static let taskToastShadowY: CGFloat = 4
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
    public static let groupedActionShadowOpacity: Double = 0.08
    public static let groupedActionShadowRadius: CGFloat = 8
    public static let groupedActionShadowY: CGFloat = 2
    public static let secondaryButtonShadowOpacity: Double = 0.08
    public static let secondaryButtonShadowRadius: CGFloat = 8
    public static let secondaryButtonShadowY: CGFloat = 2
}

public enum TaisaRadius: CGFloat, CaseIterable, Sendable {
    case listInterior = 2
    case control = 12
    case panel = 16
    case historyGroup = 20
    case composer = 24
    case circular = 9_999
}

public extension TaisaRadius {
    static let taskGroup: CGFloat = 20
    static let taskComposer: CGFloat = 28
    static let taskDue: CGFloat = 6
    static let taskToast: CGFloat = 8
}

public enum TaisaTaskSpacing {
    public static let headerGap: CGFloat = 2
    public static let dueGap: CGFloat = 6
}

public enum TaisaMaterial: Sendable, Equatable {
    case composer
    case dock

    public var reducedTransparencyFallback: TaisaColor { .raisedSurface }
}
