import XCTest

@MainActor
final class TaisaLaunchTests: XCTestCase {
    func testProductionDevelopmentShellLaunchesHomeWithoutPreviewCatalog() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(element("home.root", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Home"].exists)
        XCTAssertFalse(element("preview.catalog", in: app).exists)
        XCTAssertFalse(element("foundation.diagnostics", in: app).exists)
        retainScreenshot(of: app, name: "development-home")
    }

    func testNewStoreShowsNativeEmptyState() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Nothing here yet"].waitForExistence(timeout: 5))
        XCTAssertFalse(element("preview.catalog", in: app).exists)
        retainScreenshot(of: app, name: "development-home-empty")
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
