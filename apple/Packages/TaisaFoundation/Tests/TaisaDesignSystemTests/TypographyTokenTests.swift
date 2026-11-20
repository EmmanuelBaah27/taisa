import SwiftUI
import Testing
@testable import TaisaDesignSystem

@Suite("Native typography tokens")
struct TypographyTokenTests {
    @Test func everySemanticRoleMapsToTheApprovedBundledFamilyAndScale() {
        let expected: [TaisaTypography: ExpectedTypography] = [
            .display: .init(family: "Scoutie Sans", fontName: "ScoutieSans-SemiBold", size: 28, style: .largeTitle, weight: .semibold),
            .profileName: .init(family: "Scoutie Sans", fontName: "ScoutieSans-SemiBold", size: TaisaProfileMetric.nameSize, style: .title, weight: .semibold),
            .profileBody: .init(family: "Inter", fontName: "InterVariable", size: 16, style: .body, weight: .regular),
            .profileLabel: .init(family: "Inter", fontName: "InterVariable", size: 16, style: .body, weight: .medium),
            .profileSupporting: .init(family: "Inter", fontName: "InterVariable", size: 14, style: .subheadline, weight: .regular),
            .heading: .init(family: "Scoutie Sans", fontName: "ScoutieSans-Medium", size: 20, style: .title2, weight: .medium),
            .bodyLarge: .init(family: "Inter", fontName: "InterVariable", size: 18, style: .title3, weight: .regular),
            .body: .init(family: "Inter", fontName: "InterVariable", size: 16, style: .body, weight: .regular),
            .label: .init(family: "Inter", fontName: "InterVariable", size: 14, style: .subheadline, weight: .semibold),
            .buttonLabel: .init(family: "Inter", fontName: "InterVariable", size: 16, style: .body, weight: .medium),
            .metadata: .init(family: "Inter", fontName: "InterVariable", size: 12, style: .caption, weight: .regular),
            .navigationLabel: .init(family: "Inter", fontName: "InterVariable", size: 16, style: .body, weight: .medium),
            .supporting: .init(family: "Inter", fontName: "InterVariable", size: 14, style: .subheadline, weight: .regular),
            .childHeaderTitle: .init(family: "Inter", fontName: "InterVariable", size: 16, style: .body, weight: .semibold),
            .datedPageTitle: .init(family: "Scoutie Sans", fontName: "ScoutieSans-SemiBold", size: 28, style: .title, weight: .semibold),
            .taskTitle: .init(family: "Inter", fontName: "InterVariable", size: 16, style: .body, weight: .medium),
            .taskSupporting: .init(family: "Inter", fontName: "InterVariable", size: 14, style: .subheadline, weight: .regular),
            .sheetTitle: .init(family: "Scoutie Sans", fontName: "ScoutieSans-Medium", size: 20, style: .title3, weight: .medium),
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
            #expect(role.tracking == approvedTracking[role])
        }
    }

    @Test func sharedTextAppliesTheCompleteSemanticTextStyle() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/TaisaText.swift"),
            encoding: .utf8
        )

        #expect(source.contains(".lineSpacing(role.lineSpacing)"))
        #expect(source.contains(".tracking(role.tracking)"))
        #expect(abs(TaisaTypography.buttonLabel.lineSpacing - 4.640625) < 0.001)
        #expect(abs(TaisaTypography.supporting.lineSpacing - 3.060546875) < 0.001)
        #expect(abs(TaisaTypography.metadata.lineSpacing - 3.48046875) < 0.001)
        #expect(abs(TaisaTypography.heading.lineSpacing) < 0.001)
    }

    @Test func sharedTypographyModifierAppliesFontLeadingAndTrackingTogether() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/TaisaTypographyModifier.swift"),
            encoding: .utf8
        )

        #expect(source.contains(".font(role.font)"))
        #expect(source.contains(".lineSpacing(role.lineSpacing)"))
        #expect(source.contains(".tracking(role.tracking)"))
    }

    private var approvedLineHeight: [TaisaTypography: CGFloat] {
        [
            .display: 36,
            .profileName: TaisaProfileMetric.nameLineHeight,
            .profileBody: 24,
            .profileLabel: 24,
            .profileSupporting: 20,
            .heading: 26,
            .bodyLarge: 26,
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
            .sheetTitle: 26,
            .sectionLabel: 20,
        ]
    }

    private var approvedTracking: [TaisaTypography: CGFloat] {
        [
            .display: -0.56,
            .profileName: -0.56,
            .profileBody: -0.16,
            .profileLabel: -0.16,
            .profileSupporting: -0.14,
            .heading: -0.20,
            .bodyLarge: -0.18,
            .body: -0.16,
            .label: -0.14,
            .buttonLabel: -0.16,
            .metadata: 0,
            .navigationLabel: -0.16,
            .supporting: -0.14,
            .childHeaderTitle: -0.16,
            .datedPageTitle: -0.56,
            .taskTitle: -0.16,
            .taskSupporting: -0.14,
            .sheetTitle: -0.20,
            .sectionLabel: -0.14,
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
