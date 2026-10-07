import XCTest

@MainActor
final class TaisaAccessibilityLayoutTests: XCTestCase {
    func testAccessibilityTextKeepsHomeRowsVisibleAndHittable() {
        assertHomeScenarioFitsVisibleWindow(
            identifier: "home.accessibilityText",
            requiredText: "Plan the garden studio"
        )
    }

    func testNarrowIPadKeepsHomeRowsVisibleAndHittable() {
        assertHomeScenarioFitsVisibleWindow(
            identifier: "home.narrowIPad",
            requiredText: "Plan the garden studio"
        )
    }

    func testFailureAndRecoveryActionsRemainReachable() {
        for (identifier, action) in [("home.failure", "Try again"), ("home.recovery", "Open recovery")] {
            let app = XCUIApplication()
            openScenario(identifier, in: app)
            let control = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", action)).firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 5), identifier)
            XCTAssertTrue(control.isHittable, identifier)
            app.terminate()
        }
    }

    private func assertHomeScenarioFitsVisibleWindow(identifier: String, requiredText: String) {
        let app = XCUIApplication()
        openScenario(identifier, in: app)

        let title = app.staticTexts[requiredText]
        let action = app.buttons[requiredText]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(title.exists)
        XCTAssertTrue(action.isHittable)

        let windowFrame = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(title.frame.minX, windowFrame.minX)
        XCTAssertLessThanOrEqual(title.frame.maxX, windowFrame.maxX)
        XCTAssertGreaterThanOrEqual(action.frame.minX, windowFrame.minX)
        XCTAssertLessThanOrEqual(action.frame.maxX, windowFrame.maxX)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = identifier
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openScenario(_ identifier: String, in app: XCUIApplication) {
        app.launch()
        let search = app.searchFields["Search scenarios"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), identifier)
        search.tap()
        search.typeText(identifier)
        let title: String
        switch identifier {
        case "home.accessibilityText": title = "Home accessibility text"
        case "home.narrowIPad": title = "Home narrow iPad"
        default: title = identifier.replacingOccurrences(of: "home.", with: "Home ")
        }
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), identifier)
        row.tap()
        XCTAssertFalse(search.waitForExistence(timeout: 2), identifier)
    }
}
