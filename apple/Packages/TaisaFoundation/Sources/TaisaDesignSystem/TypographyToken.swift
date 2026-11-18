import SwiftUI

/// All native typography resolves through bundled fonts, including older shared controls.
public enum TaisaTypography: String, CaseIterable, Sendable {
    case display, profileName, profileBody, profileLabel, profileSupporting
    case heading, body, label, metadata, navigationLabel, supporting, childHeaderTitle

    public var fontName: String {
        switch self {
        case .display, .profileName: "ScoutieSans-SemiBold"
        default: "Inter-Regular"
        }
    }

    public var pointSize: CGFloat {
        switch self {
        case .display: 34
        case .profileName: TaisaProfileMetric.nameSize
        case .heading: 22
        case .profileBody, .profileLabel, .navigationLabel: 16
        case .body, .childHeaderTitle: 17
        case .label: 15
        case .metadata: 12
        case .profileSupporting, .supporting: 14
        }
    }

    public var lineHeight: CGFloat {
        switch self {
        case .display: 41
        case .profileName: TaisaProfileMetric.nameLineHeight
        case .heading: 28
        case .body, .childHeaderTitle: 22
        case .profileBody, .profileLabel, .navigationLabel: 24
        case .label, .profileSupporting, .supporting: 20
        case .metadata: 16
        }
    }

    public var relativeTextStyle: Font.TextStyle {
        switch self {
        case .display: .largeTitle
        case .profileName: .title
        case .heading: .title2
        case .profileBody, .profileLabel, .body, .navigationLabel: .body
        case .label, .profileSupporting, .supporting: .subheadline
        case .metadata: .caption
        case .childHeaderTitle: .headline
        }
    }

    public var weight: Font.Weight {
        switch self {
        case .display, .profileName, .heading, .label, .childHeaderTitle: .semibold
        case .profileLabel, .navigationLabel: .medium
        default: .regular
        }
    }

    public var font: Font {
        TaisaProfileFonts.register()
        return .custom(fontName, size: pointSize, relativeTo: relativeTextStyle).weight(weight)
    }
}
