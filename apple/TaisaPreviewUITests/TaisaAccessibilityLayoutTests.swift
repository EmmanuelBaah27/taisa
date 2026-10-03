import XCTest

@MainActor
final class TaisaAccessibilityLayoutTests: XCTestCase {
    func testAccessibilityTextKeepsContentVisibleAndHittable() {
        assertScenarioFitsVisibleWindow(identifier: "foundation.accessibilityText")
    }

    func testNarrowIPadKeepsContentVisibleAndHittable() {
        assertScenarioFitsVisibleWindow(identifier: "foundation.narrowIPad")
    }

    private func assertScenarioFitsVisibleWindow(identifier: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-TAISAPreviewScenario", identifier]
        app.launch()

        let readiness = app.descendants(matching: .any)["preview.ready.\(identifier)"]
        XCTAssertTrue(readiness.waitForExistence(timeout: 5))

        let title = app.staticTexts["preview.scenario.title"]
        let action = app.buttons["preview.scenario.primaryAction"]
        XCTAssertTrue(title.exists)
        XCTAssertTrue(action.isHittable)

        let windowFrame = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(title.frame.minX, windowFrame.minX)
        XCTAssertLessThanOrEqual(title.frame.maxX, windowFrame.maxX)
        XCTAssertGreaterThanOrEqual(action.frame.minX, windowFrame.minX)
        XCTAssertLessThanOrEqual(action.frame.maxX, windowFrame.maxX)
    }
}
