import SwiftUI
import Testing
@testable import TaisaDesignSystem

@Suite("Native typography tokens")
struct TypographyTokenTests {
    @Test func everySemanticRoleMapsToTheApprovedBundledFamilyAndScale() {
        let expected: [TaisaTypography: ExpectedTypography] = [
            .display: .init(family: "Scoutie Sans", fontName: "ScoutieSans-ExtraLight", size: 34, style: .largeTitle, weight: .semibold),
            .heading: .init(family: "Inter", fontName: "InterVariable", size: 22, style: .title2, weight: .semibold),
            .body: .init(family: "Inter", fontName: "InterVariable", size: 17, style: .body, weight: .regular),
            .label: .init(family: "Inter", fontName: "InterVariable", size: 15, style: .subheadline, weight: .semibold),
            .metadata: .init(family: "Inter", fontName: "InterVariable", size: 12, style: .caption, weight: .regular),
            .navigationLabel: .init(family: "Inter", fontName: "InterVariable", size: 16, style: .body, weight: .medium),
            .supporting: .init(family: "Inter", fontName: "InterVariable", size: 14, style: .subheadline, weight: .regular),
            .childHeaderTitle: .init(family: "Inter", fontName: "InterVariable", size: 17, style: .headline, weight: .semibold),
            .datedPageTitle: .init(family: "Scoutie Sans", fontName: "ScoutieSans-ExtraLight", size: 28, style: .title, weight: .semibold),
            .taskTitle: .init(family: "Inter", fontName: "InterVariable", size: 16, style: .body, weight: .medium),
            .taskSupporting: .init(family: "Inter", fontName: "InterVariable", size: 14, style: .subheadline, weight: .regular),
        ]

        #expect(Set(expected.keys) == Set(TaisaTypography.allCases))
        for (role, contract) in expected {
            #expect(role.familyName == contract.family)
            #expect(role.fontName == contract.fontName)
            #expect(role.pointSize == contract.size)
            #expect(role.relativeTextStyle == contract.style)
            #expect(role.weight == contract.weight)
        }
    }
}

private struct ExpectedTypography {
    let family: String
    let fontName: String
    let size: CGFloat
    let style: Font.TextStyle
    let weight: Font.Weight
}
