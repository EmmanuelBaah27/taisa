import XCTest

@MainActor
final class TaisaPreviewCatalogTests: XCTestCase {
    func testCatalogLaunchesWithNoProductionShell() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(element("preview.catalog", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("foundation.root", in: app).exists)
    }

    func testLaunchArgumentOpensAccessibilityScenario() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-TAISAPreviewScenario",
            "foundation.accessibilityText",
        ]
        app.launch()

        XCTAssertTrue(
            element("preview.ready.foundation.accessibilityText", in: app)
                .waitForExistence(timeout: 5)
        )
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
