import CoreGraphics

public enum TaisaSpacing: CGFloat, CaseIterable, Sendable {
    case tight = 4
    case compact = 8
    case standard = 16
    case section = 24
    case page = 32
}

public enum TaisaRadius: CGFloat, CaseIterable, Sendable {
    case control = 12
    case panel = 16
    case composer = 24
    case circular = 9_999
}

public enum TaisaMaterial: Sendable, Equatable {
    case composer
    case dock

    public var reducedTransparencyFallback: TaisaColor { .raisedSurface }
}
