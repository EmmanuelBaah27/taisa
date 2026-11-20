import Foundation
import Testing
@testable import TaisaDesignSystem

@Suite("Shared native button foundation")
struct ButtonMaterialRegressionTests {
    @Test func allRolesUseTheRecordButtonsNativeFoundation() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/TaisaButton.swift"), encoding: .utf8)
        let style = try String(contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/TaisaButtonStyle.swift"), encoding: .utf8)
        #expect(source.contains("TaisaButtonControl(style: TaisaButtonStyle(role: isSelected && role != .destructive ? .primary : role, shape: shape)"))
        #expect(source.contains("shape: TaisaButtonShape = .capsule"))
        #expect(style.contains(".buttonStyle(.glassProminent)"))
        #expect(!style.contains(".buttonStyle(.glass)"))
        #expect(style.contains(".glassEffect(.clear.interactive(), in: buttonShape)"))
        #expect(style.contains(".tint(TaisaColor.primaryAction.color)"))
        #expect(!source.contains(".glassEffect("))
        #expect(source.contains("TaisaControlMetric.actionButtonHeight"))
        #expect(!source.contains("buttonShape.stroke"))
        #expect(!source.contains(".background(background, in: buttonShape)"))
        #expect(style.contains("accessibilityReduceTransparency"))
    }
}
