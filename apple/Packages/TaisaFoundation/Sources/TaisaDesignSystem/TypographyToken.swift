import SwiftUI

public enum TaisaTypography: String, CaseIterable, Sendable {
    case display
    case heading
    case body
    case label
    case metadata
    case navigationLabel
    case supporting
    case childHeaderTitle
    case datedPageTitle
    case taskTitle
    case taskSupporting

    public var pointSize: CGFloat {
        switch self {
        case .navigationLabel, .taskTitle: 16
        case .supporting, .taskSupporting: 14
        case .datedPageTitle: 28
        case .childHeaderTitle: 0
        default: 0
        }
    }

    public var lineHeight: CGFloat {
        switch self {
        case .navigationLabel, .taskTitle: 24
        case .supporting, .taskSupporting: 20
        case .datedPageTitle: 36
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
        case .supporting:
            .system(size: pointSize, weight: .regular, design: .default)
        case .childHeaderTitle:
            .system(.headline, weight: .semibold)
        case .datedPageTitle:
            .custom("Scoutie Sans", size: pointSize, relativeTo: .title)
                .weight(.semibold)
        case .taskTitle:
            .custom("Inter", size: pointSize, relativeTo: .body).weight(.medium)
        case .taskSupporting:
            .custom("Inter", size: pointSize, relativeTo: .subheadline)
        }
    }
}
