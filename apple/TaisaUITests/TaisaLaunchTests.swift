import XCTest

@MainActor
final class TaisaLaunchTests: XCTestCase {
    func testProductionDevelopmentShellLaunchesWithoutPreviewCatalog() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(element("foundation.root", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["foundation.title"].exists)
        XCTAssertTrue(app.buttons["foundation.diagnostics.action"].isHittable)
        XCTAssertFalse(element("preview.catalog", in: app).exists)
        retainScreenshot(of: app, name: "development-shell")
    }

    func testDiagnosticsShowsExactBuildIdentity() {
        let app = XCUIApplication()
        app.launch()

        let diagnostics = app.buttons["foundation.diagnostics.action"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
        diagnostics.tap()
        XCTAssertTrue(
            element("foundation.diagnostics", in: app).waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Source"].exists)
        XCTAssertTrue(app.staticTexts["Build"].exists)
        XCTAssertTrue(app.staticTexts["Bundle"].exists)
        retainScreenshot(of: app, name: "build-diagnostics")
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func retainScreenshot(of app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
