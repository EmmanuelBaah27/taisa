import Testing
@testable import TaisaDesignSystem

@Suite("Design-system tokens")
struct TokenTests {
    @Test func primaryActionUsesPortableContractValue() {
        #expect(TaisaColor.primaryAction.hex == "#CDEC1A")
    }
}
