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

    func testPrimaryNavigationIsTapOnlyAndTargetsAreComfortablyHittable() {
        let app = XCUIApplication()
        app.launchArguments = ["--taisa-chats-visual-qa"]
        app.launch()

        let chats = element("conversations.root", in: app)
        XCTAssertTrue(chats.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForSelection("Chats", in: app))

        swipeRight(in: app)
        XCTAssertTrue(waitForSelection("Chats", in: app))

        app.buttons["Home"].tap()
        XCTAssertTrue(waitForSelection("Home", in: app))

        swipeLeft(in: app)
        XCTAssertTrue(waitForSelection("Home", in: app))

        app.buttons["You"].tap()
        XCTAssertTrue(waitForSelection("You", in: app))

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
        XCTAssertEqual(row.frame.minX, window.minX + 16, accuracy: 1)
        XCTAssertEqual(row.frame.maxX, window.maxX - 16, accuracy: 1)
        XCTAssertTrue(app.buttons["Talk to Taisa, starts recording"].isHittable)
        XCTAssertLessThanOrEqual(app.buttons["Talk to Taisa, starts recording"].frame.maxX, window.maxX)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func waitForSelection(_ label: String, in app: XCUIApplication) -> Bool {
        let selected = NSPredicate(format: "selected == true")
        let expectation = XCTNSPredicateExpectation(predicate: selected, object: app.buttons[label])
        return XCTWaiter.wait(for: [expectation], timeout: 2) == .completed
    }

    private func swipeLeft(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.12))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.12))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func swipeRight(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.12))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.12))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func retainScreenshot(of app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
