import SwiftUI

public enum TaisaTypography: String, CaseIterable, Sendable {
    case display
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

    public var familyName: String {
        switch self {
        case .display, .datedPageTitle: "Scoutie Sans"
        default: "Inter"
        }
    }

    public var fontName: String {
        switch self {
        case .display, .datedPageTitle: "ScoutieSans-ExtraLight"
        default: "InterVariable"
        }
    }

    public var pointSize: CGFloat {
        switch self {
        case .display: 34
        case .heading: 22
        case .body: 17
        case .label, .buttonLabel: 15
        case .metadata: 12
        case .navigationLabel, .taskTitle: 16
        case .supporting, .taskSupporting: 14
        case .childHeaderTitle: 17
        case .datedPageTitle: 28
        }
    }

    public var lineHeight: CGFloat {
        switch self {
        case .display: 41
        case .heading: 28
        case .body, .childHeaderTitle: 22
        case .label, .buttonLabel, .supporting, .taskSupporting: 20
        case .metadata: 16
        case .navigationLabel, .taskTitle: 24
        case .datedPageTitle: 36
        }
    }

    public var relativeTextStyle: Font.TextStyle {
        switch self {
        case .display: .largeTitle
        case .heading: .title2
        case .body, .navigationLabel, .taskTitle: .body
        case .label, .buttonLabel, .supporting, .taskSupporting: .subheadline
        case .metadata: .caption
        case .childHeaderTitle: .headline
        case .datedPageTitle: .title
        }
    }

    public var weight: Font.Weight {
        switch self {
        case .display, .heading, .label, .childHeaderTitle, .datedPageTitle: .semibold
        case .buttonLabel, .navigationLabel, .taskTitle: .medium
        case .body, .metadata, .supporting, .taskSupporting: .regular
        }
    }

    public var font: Font {
        .custom(fontName, size: pointSize, relativeTo: relativeTextStyle)
            .weight(weight)
    }
}
