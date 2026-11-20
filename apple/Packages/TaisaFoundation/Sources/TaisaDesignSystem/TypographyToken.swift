import SwiftUI

public enum TaisaTypography: String, CaseIterable, Sendable {
    case display
    case profileName, profileBody, profileLabel, profileSupporting
    case heading
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
        case .display, .datedPageTitle, .profileName: "Scoutie Sans"
        default: "Inter"
        }
    }

    public var fontName: String {
        switch self {
        case .display, .datedPageTitle: "ScoutieSans-ExtraLight"
        case .profileName: "ScoutieSans-SemiBold"
        default: "InterVariable"
        }
    }

    public var pointSize: CGFloat {
        switch self {
        case .display: 34
        case .profileName: TaisaProfileMetric.nameSize
        case .profileBody, .profileLabel: 16
        case .profileSupporting: 14
        case .heading: 22
        case .body, .buttonLabel, .navigationLabel, .childHeaderTitle, .taskTitle: 16
        case .label, .supporting, .taskSupporting, .sectionLabel: 14
        case .metadata: 12
        case .datedPageTitle: 28
        case .sheetTitle: 20
        }
    }

    public var lineHeight: CGFloat {
        switch self {
        case .display: 41
        case .profileName: TaisaProfileMetric.nameLineHeight
        case .profileBody, .profileLabel: 24
        case .profileSupporting: 20
        case .heading: 28
        case .body, .buttonLabel, .navigationLabel, .childHeaderTitle, .taskTitle: 24
        case .label, .supporting, .taskSupporting, .sectionLabel: 20
        case .metadata: 18
        case .datedPageTitle: 36
        case .sheetTitle: 28
        }
    }

    public var relativeTextStyle: Font.TextStyle {
        switch self {
        case .display: .largeTitle
        case .profileName: .title
        case .profileBody, .profileLabel: .body
        case .profileSupporting: .subheadline
        case .heading: .title2
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

    public var weight: Font.Weight {
        switch self {
        case .display, .heading, .label, .childHeaderTitle, .datedPageTitle, .profileName: .semibold
        case .buttonLabel, .navigationLabel, .taskTitle, .sheetTitle, .sectionLabel, .profileLabel: .medium
        case .body, .metadata, .supporting, .taskSupporting, .profileBody, .profileSupporting: .regular
        }
    }

    public var font: Font {
        TaisaProfileFonts.register()
        return .custom(fontName, size: pointSize, relativeTo: relativeTextStyle)
            .weight(weight)
    }
}
