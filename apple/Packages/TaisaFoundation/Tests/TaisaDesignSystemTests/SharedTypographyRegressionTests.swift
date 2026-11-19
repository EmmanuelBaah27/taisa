import CoreText
import SwiftUI
import Testing
@testable import TaisaDesignSystem

@Suite("Shared typography adoption")
struct SharedTypographyRegressionTests {
    @Test func recoveryButtonAndHeaderUseTheSameBundledFamilyAsSupportingCopy() {
        TaisaProfileFonts.register()
        #expect(TaisaTypography.label.font == Font.custom("Inter-Regular", size: 15, relativeTo: .subheadline).weight(.semibold))
        #expect(TaisaTypography.childHeaderTitle.font == Font.custom("Inter-Regular", size: 17, relativeTo: .headline).weight(.semibold))
        #expect(TaisaTypography.profileSupporting.font == Font.custom("Inter-Regular", size: 14, relativeTo: .subheadline).weight(.regular))
    }

    @Test func bundledFamiliesResolveWithoutSystemFallback() {
        TaisaProfileFonts.register()
        for (name, family) in [("Inter-Regular", "Inter"), ("ScoutieSans-SemiBold", "Scoutie Sans")] {
            let font = CTFontCreateWithName(name as CFString, 16, nil)
            #expect(CTFontCopyPostScriptName(font) as String == name)
            #expect(CTFontCopyFamilyName(font) as String == family)
        }
    }
}
