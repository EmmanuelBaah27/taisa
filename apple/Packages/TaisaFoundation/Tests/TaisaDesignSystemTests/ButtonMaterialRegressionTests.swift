import Foundation
import Testing
@testable import TaisaDesignSystem

@Suite("Shared native button foundation")
struct ButtonMaterialRegressionTests {
    @Test func allRolesUseTheRecordButtonsNativeFoundation() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/TaisaButton.swift"), encoding: .utf8)
        let style = try String(contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/TaisaButtonStyle.swift"), encoding: .utf8)
        let control = try String(contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/TaisaButtonControl.swift"), encoding: .utf8)
        #expect(source.contains("TaisaButtonStyle(role: effectiveRole, shape: shape, size: size)"))
        #expect(control.contains(".taisaButtonSurface(role: effectiveRole, size: style.size, shape: style.shape)"))
        #expect(source.contains("shape: TaisaButtonShape = .capsule"))
        #expect(style.contains(".buttonStyle(.glassProminent)"))
        #expect(!style.contains(".buttonStyle(.glass)"))
        #expect(style.contains(".glassEffect(.clear.interactive(), in: buttonShape)"))
        #expect(style.contains(".controlSize(size.controlSize)"))
        let surface = try String(contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/TaisaSecondaryButtonSurface.swift"), encoding: .utf8)
        #expect(surface.contains(".glassEffect(.clear.interactive(), in: surfaceShape)"))
        #expect(!surface.contains("case .secondary, .ghost, .destructive:"))
        #expect(style.contains(".tint(TaisaColor.primaryAction.color)"))
        #expect(!source.contains(".glassEffect("))
        #expect(source.contains("size: TaisaButtonSize = .standard"))
        #expect(!source.contains("buttonShape.stroke"))
        #expect(!source.contains(".background(background, in: buttonShape)"))
        #expect(style.contains("accessibilityReduceTransparency"))
    }
}
