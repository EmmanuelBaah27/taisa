import Foundation
import XCTest

final class NavigationTypographyContractTests: XCTestCase {
    func testAuthoredNavigationTitlesUseTheSharedSemanticModifier() throws {
        let appleRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let chrome = try String(
            contentsOf: appleRoot.appendingPathComponent("Packages/TaisaFoundation/Sources/TaisaDesignSystem/TaisaPageChrome.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(chrome.contains("func taisaNavigationTitle"))
        XCTAssertTrue(chrome.contains(".navigationTitle(title)"), "Keep native route and Back semantics")
        XCTAssertTrue(chrome.contains("ToolbarItem(placement: .principal)"))
        XCTAssertTrue(chrome.contains("TaisaText(role: .childHeaderTitle"))
        XCTAssertTrue(chrome.contains(".navigationBarTitleDisplayMode(.inline)"))
        XCTAssertTrue(chrome.contains(".accessibilityHidden(true)"), "The visible principal title must not duplicate the native navigation title in accessibility")
        XCTAssertTrue(chrome.contains(".accessibilityRepresentation"), "Toolbar bridging must replace the decorative title's accessibility representation")
        XCTAssertFalse(chrome.contains("taisa.navigation-title"), "A UI-test identifier must not re-expose the decorative principal title to accessibility")

        let productRoot = appleRoot.appendingPathComponent("TaisaApp")
        let productSources = try swiftSources(in: productRoot).joined(separator: "\n")
        XCTAssertFalse(productSources.contains(".navigationTitle("))
        XCTAssertTrue(productSources.contains(".taisaNavigationTitle("))
    }

    func testApplicationRootsProvideInterAsTheDefaultSemanticBodyFont() throws {
        let appleRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for relativePath in ["TaisaApp/TaisaApp.swift", "TaisaPreview/TaisaPreviewApp.swift"] {
            let source = try String(contentsOf: appleRoot.appendingPathComponent(relativePath), encoding: .utf8)
            XCTAssertTrue(source.contains(".taisaTypography(.body)"), "Missing complete default DS typography in \(relativePath)")
        }
    }

    private func swiftSources(in root: URL) throws -> [String] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys)
        return try (files?.compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension == "swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
    }
}
