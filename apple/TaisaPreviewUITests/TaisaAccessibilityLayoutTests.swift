import XCTest

@MainActor
final class TaisaAccessibilityLayoutTests: XCTestCase {
    func testAccessibilityTextKeepsHomeRowsVisibleAndHittable() {
        assertHomeScenarioFitsVisibleWindow(
            identifier: "home.accessibilityText",
            requiredText: "Your best planning sessions happen before midday.",
            actionLabel: "home.lead-insight"
        )
    }

    func testNarrowIPadKeepsHomeRowsVisibleAndHittable() {
        assertHomeScenarioFitsVisibleWindow(
            identifier: "home.narrowIPad",
            requiredText: "Plan the garden studio"
        )
    }

    func testCombinedHomeKeepsWeeklyWorkAndInsightReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["-TAISAPreviewScenario", "home.combined"]
        app.launch()

        let weeklyWork = app.staticTexts["Draft the studio lighting plan"]
        XCTAssertTrue(weeklyWork.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Complete Draft the studio lighting plan"].isHittable)
        let insight = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Your best planning sessions happen before midday.")
        ).firstMatch
        XCTAssertTrue(insight.waitForExistence(timeout: 5))
        XCTAssertTrue(insight.isHittable)
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

    private func assertHomeScenarioFitsVisibleWindow(
        identifier: String,
        requiredText: String,
        actionLabel: String? = nil
    ) {
        let app = XCUIApplication()
        openScenario(identifier, in: app)

        let title = app.staticTexts[requiredText]
        let action = app.buttons[actionLabel ?? requiredText]
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
