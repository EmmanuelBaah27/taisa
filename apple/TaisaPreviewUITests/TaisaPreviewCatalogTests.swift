import XCTest

@MainActor
final class TaisaPreviewCatalogTests: XCTestCase {
    func testCatalogLaunchesWithNoProductionShell() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(element("preview.catalog", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("foundation.root", in: app).exists)
        retainScreenshot(of: app, name: "preview-catalog")
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
        retainScreenshot(of: app, name: "preview-accessibility-text")
    }

    func testRepresentativeHomeScenariosOpenDeterministically() {
        for scenario in ["home.empty", "home.content", "home.failure"] {
            let app = XCUIApplication()
            app.launch()
            let search = app.searchFields["Search scenarios"]
            XCTAssertTrue(search.waitForExistence(timeout: 5), scenario)
            search.tap()
            search.typeText(scenario)
            let title = scenario.replacingOccurrences(of: "home.", with: "Home ")
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), scenario)
            row.tap()
            XCTAssertFalse(search.waitForExistence(timeout: 2), scenario)
            app.terminate()
        }
    }

    func testCombinedHomeOpensNestedInsights() {
        let app = XCUIApplication()
        app.launchArguments = ["-TAISAPreviewScenario", "home.combined"]
        app.launch()

        let weeklyWork = app.staticTexts["Draft the studio lighting plan"]
        XCTAssertTrue(weeklyWork.waitForExistence(timeout: 5))
        let insight = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Your best planning sessions happen before midday.")
        ).firstMatch
        XCTAssertTrue(insight.waitForExistence(timeout: 5))
        insight.tap()
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Needs review"].exists)
        XCTAssertTrue(app.staticTexts["History"].exists)
    }

    func testCombinedHomeOpensCompletionEvidenceBeforeCompleting() {
        let app = XCUIApplication()
        app.launchArguments = ["-TAISAPreviewScenario", "home.combined"]
        app.launch()

        let complete = app.buttons["Complete Draft the studio lighting plan"]
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        complete.tap()
        XCTAssertTrue(element("home.this-week.completion-evidence", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["What shows this is complete?"].exists)
        XCTAssertFalse(app.buttons["Complete action"].isEnabled)
    }

    func testCareerActionScenarioShowsCanonicalDetailHierarchy() {
        let app = XCUIApplication()
        app.launchArguments = ["-TAISAPreviewScenario", "career.action"]
        app.launch()

        XCTAssertTrue(element("career-work.action.detail", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Outline first case study"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Checklist"].exists)
        XCTAssertTrue(app.staticTexts["Evidence"].exists)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["History"].waitForExistence(timeout: 5))
        retainScreenshot(of: app, name: "career-action-detail")
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
