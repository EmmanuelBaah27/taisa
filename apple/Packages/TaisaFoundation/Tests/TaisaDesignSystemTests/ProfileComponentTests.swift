import CoreText
import Foundation
import Testing
@testable import TaisaDesignSystem

struct ProfileComponentTests {
    @Test func bundledProfileFontsResolveTheirRealPostscriptNames() {
        TaisaProfileFonts.register()
        for name in ["ScoutieSans-SemiBold", "Inter-Regular", "Inter-Regular_Medium"] {
            let font = CTFontCreateWithName(name as CFString, 16, nil)
            #expect(CTFontCopyPostScriptName(font) as String == name)
        }
    }

    @Test func profileFieldAdditionRetainsExistingDefaultContracts() {
        #expect(TaisaProfileMetric.avatar == TaisaSecondaryButtonSize.standard.visualSize)
        #expect(TaisaProfileMetric.editorAvatar == 56)
        #expect(TaisaProfileMetric.chevron == 20)
        #expect(TaisaTypography.allCases.contains(.profileName))
        #expect(TaisaTypography.allCases.contains(.profileBody))
        #expect(TaisaTypography.allCases.contains(.profileSupporting))
        #expect(TaisaControlMetric.headerActionHeight >= 44)
    }

    @Test func profileEditUsesTheSharedDefaultSecondaryIconButton() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/TaisaProfileIconButton.swift"),
            encoding: .utf8
        )

        #expect(source.contains("TaisaSecondaryIconButton("))
        #expect(source.contains("size: .standard"))
        #expect(source.contains("iconColor: .foreground"))
        #expect(!source.contains("iconColor: .mutedForeground"))
        #expect(!source.contains("TaisaButtonControl("))
        #expect(!source.contains(".frame(minWidth:"))
    }
}
