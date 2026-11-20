import SwiftUI

public enum TaisaTypography: String, CaseIterable, Sendable {
    case display
    case profileName
    case profileBody
    case profileLabel
    case profileSupporting
    case heading
    case body
    case label
    case metadata
    case navigationLabel
    case supporting
    case childHeaderTitle

    public var pointSize: CGFloat {
        switch self {
        case .navigationLabel: 16
        case .supporting: 14
        case .childHeaderTitle: 0
        default: 0
        }
    }

    public var lineHeight: CGFloat {
        switch self {
        case .navigationLabel: 24
        case .supporting: 20
        default: 0
        }
    }

    public var font: Font {
        switch self {
        case .profileName:
            TaisaProfileFonts.register()
            return .custom("ScoutieSans-SemiBold", size: TaisaProfileMetric.nameSize, relativeTo: .title).weight(.semibold)
        case .profileLabel:
            TaisaProfileFonts.register()
            return .custom("Inter-Regular_Medium", size: 16, relativeTo: .body)
        case .profileBody:
            TaisaProfileFonts.register()
            return .custom("Inter-Regular", size: 16, relativeTo: .body)
        case .profileSupporting:
            TaisaProfileFonts.register()
            return .custom("Inter-Regular", size: 14, relativeTo: .subheadline)
        case .display:
            return .system(.largeTitle, design: .rounded, weight: .semibold)
        case .heading:
            return .system(.title2, design: .rounded, weight: .semibold)
        case .body:
            return .system(.body, design: .rounded, weight: .regular)
        case .label:
            return .system(.subheadline, design: .rounded, weight: .semibold)
        case .metadata:
            return .system(.caption, design: .rounded, weight: .regular)
        case .navigationLabel:
            return .system(size: pointSize, weight: .medium, design: .default)
        case .supporting:
            return .system(size: pointSize, weight: .regular, design: .default)
        case .childHeaderTitle:
            return .system(.headline, weight: .semibold)
        }
    }
}
