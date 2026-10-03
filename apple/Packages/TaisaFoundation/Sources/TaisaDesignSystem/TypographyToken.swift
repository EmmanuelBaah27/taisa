import SwiftUI

public enum TaisaTypography: String, CaseIterable, Sendable {
    case display
    case heading
    case body
    case label
    case metadata

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
        }
    }
}
