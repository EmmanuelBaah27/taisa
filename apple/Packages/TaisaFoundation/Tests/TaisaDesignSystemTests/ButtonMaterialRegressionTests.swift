import Foundation
import Testing
@testable import TaisaDesignSystem

@Suite("Authored button material")
struct ButtonMaterialRegressionTests {
    @Test func secondaryRecoveryButtonUsesApprovedGlassInsteadOfTheRetiredOutline() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/TaisaButton.swift"), encoding: .utf8)
        #expect(source.contains(".glassEffect(.clear.interactive(), in: buttonShape)"))
        #expect(source.contains("TaisaControlMetric.actionButtonHeight"))
        #expect(!source.contains("buttonShape.stroke"))
        #expect(!source.contains(".background(background, in: buttonShape)"))
        #expect(source.contains("accessibilityReduceTransparency"))
    }
}
