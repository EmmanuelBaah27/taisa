import SwiftUI

public enum TaisaTypography: String, CaseIterable, Sendable {
    case display
    case profileName, profileBody, profileLabel, profileSupporting
    case heading
    case bodyLarge
    case body
    case label
    case buttonLabel
    case metadata
    case navigationLabel
    case supporting
    case childHeaderTitle
    case datedPageTitle
    case taskTitle
    case taskSupporting
    case sheetTitle
    case sectionLabel

    public var familyName: String {
        switch self {
        case .display, .heading, .datedPageTitle, .profileName, .sheetTitle: "Scoutie Sans"
        default: "Inter"
        }
    }

    public var fontName: String {
        switch self {
        case .display, .datedPageTitle, .profileName: "ScoutieSans-SemiBold"
        case .heading, .sheetTitle: "ScoutieSans-Medium"
        default: "InterVariable"
        }
    }

    public var pointSize: CGFloat {
        switch self {
        case .display: 28
        case .profileName: TaisaProfileMetric.nameSize
        case .profileBody, .profileLabel: 16
        case .profileSupporting: 14
        case .heading: 20
        case .bodyLarge: 18
        case .body, .buttonLabel, .navigationLabel, .childHeaderTitle, .taskTitle: 16
        case .label, .supporting, .taskSupporting, .sectionLabel: 14
        case .metadata: 12
        case .datedPageTitle: 28
        case .sheetTitle: 20
        }
    }

    public var lineHeight: CGFloat {
        switch self {
        case .display: 36
        case .profileName: TaisaProfileMetric.nameLineHeight
        case .profileBody, .profileLabel: 24
        case .profileSupporting: 20
        case .heading: 26
        case .bodyLarge: 26
        case .body, .buttonLabel, .navigationLabel, .childHeaderTitle, .taskTitle: 24
        case .label, .supporting, .taskSupporting, .sectionLabel: 20
        case .metadata: 18
        case .datedPageTitle: 36
        case .sheetTitle: 26
        }
    }

    public var relativeTextStyle: Font.TextStyle {
        switch self {
        case .display: .largeTitle
        case .profileName: .title
        case .profileBody, .profileLabel: .body
        case .profileSupporting: .subheadline
        case .heading: .title2
        case .bodyLarge: .title3
        case .body, .buttonLabel, .navigationLabel, .childHeaderTitle, .taskTitle: .body
        case .label, .supporting, .taskSupporting, .sectionLabel: .subheadline
        case .metadata: .caption
        case .datedPageTitle: .title
        case .sheetTitle: .title3
        }
    }

    public var lineSpacing: CGFloat {
        max(0, lineHeight - pointSize)
    }

    public var tracking: CGFloat {
        switch self {
        case .display, .profileName, .datedPageTitle:
            pointSize * -0.02
        case .metadata:
            0
        default:
            pointSize * -0.01
        }
    }

    public var weight: Font.Weight {
        switch self {
        case .display, .label, .childHeaderTitle, .datedPageTitle, .profileName: .semibold
        case .heading, .buttonLabel, .navigationLabel, .taskTitle, .sheetTitle, .sectionLabel, .profileLabel: .medium
        case .bodyLarge, .body, .metadata, .supporting, .taskSupporting, .profileBody, .profileSupporting: .regular
        }
    }

    public var font: Font {
        TaisaProfileFonts.register()
        return .custom(fontName, size: pointSize, relativeTo: relativeTextStyle)
            .weight(weight)
    }
}
