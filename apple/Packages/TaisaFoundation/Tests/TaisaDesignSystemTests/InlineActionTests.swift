import Testing
@testable import TaisaDesignSystem

@Suite("Inline content actions")
struct InlineActionTests {
    @Test func stylesResolveToExistingSemanticColors() {
        #expect(TaisaInlineActionStyle.standard.foregroundColor(isSelected: false) == .foreground)
        #expect(TaisaInlineActionStyle.muted.foregroundColor(isSelected: false) == .inactiveForeground)
        #expect(TaisaInlineActionStyle.muted.foregroundColor(isSelected: true) == .mutedForeground)
        #expect(TaisaInlineActionStyle.accent.foregroundColor(isSelected: false) == .primaryAction)
        #expect(TaisaInlineActionStyle.destructive.foregroundColor(isSelected: false) == .destructive)
    }

    @Test func contractKeepsVisibleContentFlushInsideAMobileTapTarget() {
        #expect(TaisaInlineActionContract.minimumHitHeight == 44)
        #expect(TaisaInlineActionContract.hasVisibleContainer == false)
        #expect(TaisaInlineActionContract.horizontalContentPadding == 0)
    }
}
