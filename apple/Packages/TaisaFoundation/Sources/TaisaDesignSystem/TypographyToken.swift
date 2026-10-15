import SwiftUI

public enum TaisaTypography: String, CaseIterable, Sendable {
    case display
    case heading
    case body
    case label
    case metadata
    case navigationLabel

    public var pointSize: CGFloat {
        switch self {
        case .navigationLabel: 16
        default: 0
        }
    }

    public var lineHeight: CGFloat {
        switch self {
        case .navigationLabel: 24
        default: 0
        }
    }

    public var font: Font {
        switch self {
        case .display:
            .system(.largeTitle, design: .rounded, weight: .semibold)
        case .heading:
            .system(.title2, design: .rounded, weight: .semibold)
        case .body:
            .system(.body, design: .rounded, weight: .regular)
        case .label:
            .system(.subheadline, design: .rounded, weight: .semibold)
        case .metadata:
            .system(.caption, design: .rounded, weight: .regular)
        case .navigationLabel:
            .system(size: pointSize, weight: .medium, design: .default)
        }
    }
}
