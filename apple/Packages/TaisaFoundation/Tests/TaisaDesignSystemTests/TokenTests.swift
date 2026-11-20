import Testing
@testable import TaisaDesignSystem

@Suite("Design-system tokens")
struct TokenTests {
    @Test func primaryActionUsesPortableContractValue() {
        #expect(TaisaColor.primaryAction.hex == "#E7BB0D")
    }

    @Test func allButtonsExposeOnlyStandardAndSmallSizes() {
        #expect(TaisaButtonSize.allCases == [.standard, .small])
        #expect(TaisaButtonSize.standard.visualSize == 48)
        #expect(TaisaButtonSize.small.visualSize == 36)
        #expect(TaisaButtonSize.standard.minimumHitSize == 48)
        #expect(TaisaButtonSize.small.minimumHitSize == 44)
        #expect(TaisaButtonSize.standard.hitSlop == 0)
        #expect(TaisaButtonSize.small.hitSlop == 4)
    }
}
