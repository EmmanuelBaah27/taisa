import XCTest

@MainActor
final class TaisaLaunchTests: XCTestCase {
    func testProductionDevelopmentShellLaunchesHomeWithoutPreviewCatalog() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(element("home.root", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Home"].exists)
        XCTAssertTrue(element("app-shell.primary-navigation", in: app).exists)
        XCTAssertTrue(element("app-shell.conversation-dock", in: app).exists)
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

    func testPrimaryPagerSwipesBothDirectionsAndNavigationTargetsAreComfortablyHittable() {
        let app = XCUIApplication()
        app.launchArguments = ["--taisa-chats-visual-qa"]
        app.launch()

        let chats = element("conversations.root", in: app)
        XCTAssertTrue(chats.waitForExistence(timeout: 5))

        app.swipeRight()
        XCTAssertTrue(app.staticTexts["Nothing here yet"].waitForExistence(timeout: 2))

        app.swipeLeft()
        XCTAssertTrue(chats.waitForExistence(timeout: 2))
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["Your settings and preferences will appear here."].waitForExistence(timeout: 2))

        app.swipeRight()
        XCTAssertTrue(chats.waitForExistence(timeout: 2))

        for label in ["Home", "Chats", "You"] {
            let destination = app.buttons[label]
            XCTAssertTrue(destination.exists)
            XCTAssertTrue(destination.isHittable)
            XCTAssertGreaterThanOrEqual(destination.frame.width, 55.5)
            XCTAssertGreaterThanOrEqual(destination.frame.height, 47.5)
        }
    }

    func testChatsLayoutUsesResponsivePageInsets() {
        let app = XCUIApplication()
        app.launchArguments = ["--taisa-chats-visual-qa"]
        app.launch()

        let row = element("conversation.history.row.00000000-0000-4000-8000-000000000811", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(row.frame.minX, window.minX + 20, accuracy: 1)
        XCTAssertEqual(row.frame.maxX, window.maxX - 20, accuracy: 1)
        XCTAssertTrue(app.buttons["Talk to Taisa, starts recording"].isHittable)
        XCTAssertLessThanOrEqual(app.buttons["Talk to Taisa, starts recording"].frame.maxX, window.maxX)
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
