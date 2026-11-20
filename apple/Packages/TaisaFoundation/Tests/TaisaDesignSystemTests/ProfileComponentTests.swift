import CoreText
import SwiftUI
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
        #expect(TaisaProfileMetric.avatar == TaisaControlMetric.headerActionHeight)
        #expect(TaisaProfileMetric.editorAvatar == 56)
        #expect(TaisaProfileMetric.chevron == 20)
        #expect(TaisaTypography.allCases.contains(.profileName))
        #expect(TaisaTypography.allCases.contains(.profileBody))
        #expect(TaisaTypography.allCases.contains(.profileSupporting))
        #expect(TaisaControlMetric.headerActionHeight >= 44)
        #expect(TaisaButtonControl<EmptyView>.Contract.supportsCustomContent)
    }

    @Test func profileComponentsExposeTheirUserVisibleContracts() {
        #expect(TaisaProfileAvatar.Contract.fallbackAsset == "ProfileAvatarFallback")
        #expect(TaisaProfileIconButton.Contract.minimumTarget == 44)
        #expect(TaisaProfileSummary.Contract.displayName(for: "") == "Your profile")
        #expect(TaisaProfileSummary.Contract.displaysBio("Product designer"))
        #expect(!TaisaProfileSummary.Contract.displaysBio(""))
        #expect(TaisaSettingsNavigationRow.Contract.chevron == .profileChevron)
        #expect(TaisaSettingsNavigationRow.Contract.hint(for: "Diagnostics") == "Opens Diagnostics")
        #expect(TaisaSettingsGroup<EmptyView>.Contract.radius == TaisaRadius.historyGroup.rawValue)
        #expect(TaisaProfileSection<EmptyView>.Contract.radius == TaisaRadius.historyGroup.rawValue)
    }

    @Test func profileFieldAppearanceKeepsOneSemanticStyleContract() {
        let style = TaisaFieldAppearance.profile.style
        #expect(style.titleRole == .profileSupporting)
        #expect(style.titleColor == .mutedForeground)
        #expect(style.fieldTypography == .profileBody)
        #expect(style.background == .subtleSurface)
        #expect(style.minimumHeight == TaisaControlMetric.primaryNavigationItemHeight)
        #expect(style.border == nil)
    }

    @Test func profileCentralIconsResolveToPackageAssets() {
        let expected: [(CentralIconName, String)] = [
            (.profileShield, "ProfileShield"),
            (.profileCloud, "ProfileCloud"),
            (.profileDiagnostics, "ProfileDiagnostics"),
            (.profileChevron, "ProfileChevron"),
            (.profileEdit, "ProfileEdit"),
            (.profileClose, "ProfileClose"),
        ]
        for (icon, asset) in expected {
            #expect(icon.rendering == .asset(asset))
        }
        #expect(CentralIconName.homeLine.rendering == .drawn)
    }
}
