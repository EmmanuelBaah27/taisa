import SwiftUI
import Testing
@testable import TaisaDesignSystem

@Suite("Native typography tokens")
struct TypographyTokenTests {
    @Test func everySemanticRoleMapsToTheApprovedBundledFamilyAndScale() {
        let expected: [TaisaTypography: ExpectedTypography] = [
            .display: .init(family: "Scoutie Sans", fontName: "ScoutieSans-ExtraLight", size: 34, style: .largeTitle, weight: .semibold),
            .profileName: .init(family: "Scoutie Sans", fontName: "ScoutieSans-SemiBold", size: TaisaProfileMetric.nameSize, style: .title, weight: .semibold),
            .profileBody: .init(family: "Inter", fontName: "InterVariable", size: 16, style: .body, weight: .regular),
            .profileLabel: .init(family: "Inter", fontName: "InterVariable", size: 16, style: .body, weight: .medium),
            .profileSupporting: .init(family: "Inter", fontName: "InterVariable", size: 14, style: .subheadline, weight: .regular),
            .heading: .init(family: "Inter", fontName: "InterVariable", size: 22, style: .title2, weight: .semibold),
            .body: .init(family: "Inter", fontName: "InterVariable", size: 16, style: .body, weight: .regular),
            .label: .init(family: "Inter", fontName: "InterVariable", size: 14, style: .subheadline, weight: .semibold),
            .buttonLabel: .init(family: "Inter", fontName: "InterVariable", size: 16, style: .body, weight: .medium),
            .metadata: .init(family: "Inter", fontName: "InterVariable", size: 12, style: .caption, weight: .regular),
            .navigationLabel: .init(family: "Inter", fontName: "InterVariable", size: 16, style: .body, weight: .medium),
            .supporting: .init(family: "Inter", fontName: "InterVariable", size: 14, style: .subheadline, weight: .regular),
            .childHeaderTitle: .init(family: "Inter", fontName: "InterVariable", size: 16, style: .body, weight: .semibold),
            .datedPageTitle: .init(family: "Scoutie Sans", fontName: "ScoutieSans-ExtraLight", size: 28, style: .title, weight: .semibold),
            .taskTitle: .init(family: "Inter", fontName: "InterVariable", size: 16, style: .body, weight: .medium),
            .taskSupporting: .init(family: "Inter", fontName: "InterVariable", size: 14, style: .subheadline, weight: .regular),
            .sheetTitle: .init(family: "Inter", fontName: "InterVariable", size: 20, style: .title3, weight: .medium),
            .sectionLabel: .init(family: "Inter", fontName: "InterVariable", size: 14, style: .subheadline, weight: .medium),
        ]

        #expect(Set(expected.keys) == Set(TaisaTypography.allCases))
        for (role, contract) in expected {
            #expect(role.familyName == contract.family)
            #expect(role.fontName == contract.fontName)
            #expect(role.pointSize == contract.size)
            #expect(role.lineHeight == approvedLineHeight[role])
            #expect(role.relativeTextStyle == contract.style)
            #expect(role.weight == contract.weight)
        }
    }

    @Test func sharedTextAppliesTheSemanticLineHeight() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/TaisaText.swift"),
            encoding: .utf8
        )

        #expect(source.contains(".lineSpacing(role.lineSpacing)"))
        #expect(TaisaTypography.buttonLabel.lineSpacing == 8)
        #expect(TaisaTypography.supporting.lineSpacing == 6)
        #expect(TaisaTypography.metadata.lineSpacing == 6)
    }

    private var approvedLineHeight: [TaisaTypography: CGFloat] {
        [
            .display: 41,
            .profileName: TaisaProfileMetric.nameLineHeight,
            .profileBody: 24,
            .profileLabel: 24,
            .profileSupporting: 20,
            .heading: 28,
            .body: 24,
            .label: 20,
            .buttonLabel: 24,
            .metadata: 18,
            .navigationLabel: 24,
            .supporting: 20,
            .childHeaderTitle: 24,
            .datedPageTitle: 36,
            .taskTitle: 24,
            .taskSupporting: 20,
            .sheetTitle: 28,
            .sectionLabel: 20,
        ]
    }
}

private struct ExpectedTypography {
    let family: String
    let fontName: String
    let size: CGFloat
    let style: Font.TextStyle
    let weight: Font.Weight
}
