import CoreText
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
        #expect(TaisaProfileMetric.avatar == 32)
        #expect(TaisaProfileMetric.editorAvatar == 56)
        #expect(TaisaProfileMetric.chevron == 20)
        #expect(TaisaTypography.allCases.contains(.profileName))
        #expect(TaisaTypography.allCases.contains(.profileBody))
        #expect(TaisaTypography.allCases.contains(.profileSupporting))
        #expect(TaisaControlMetric.headerActionHeight >= 44)
    }
}
