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

    func testInsightsScenarioShowsNestedInsightHierarchy() {
        let app = XCUIApplication()
        app.launchArguments = ["-TAISAPreviewScenario", "home.insights"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Needs review"].exists)
        XCTAssertTrue(app.staticTexts["History"].exists)
    }

    func testCombinedHomeRoutesCurrentFocusWithoutCompletionManagement() {
        let app = XCUIApplication()
        app.launchArguments = ["-TAISAPreviewScenario", "home.combined"]
        app.launch()

        let action = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Draft Peu Commun pitch deck")).firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertTrue(action.isHittable)
        XCTAssertFalse(app.buttons["Complete Draft Peu Commun pitch deck"].exists)
        XCTAssertFalse(element("home.this-week.completion-evidence", in: app).exists)
    }

    func testTaskComposerCreatesAndRevealsTaskOnHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-TAISAPreviewScenario", "home.taskComposer"]
        app.launch()

        XCTAssertTrue(element("preview.ready.home.taskComposer", in: app).waitForExistence(timeout: 5))
        let due = app.buttons["Due"]
        XCTAssertTrue(due.waitForExistence(timeout: 5))
        due.tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        let selectedDueDate = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Due date,")
        ).firstMatch
        XCTAssertTrue(selectedDueDate.waitForExistence(timeout: 5))
        XCTAssertNotEqual(selectedDueDate.label, "Due")
        let title = app.textFields["Task title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Book electrician")
        let submit = app.buttons["Save task"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        submit.tap()

        XCTAssertTrue(app.staticTexts["Task added"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Book electrician"].waitForExistence(timeout: 5))
        XCTAssertFalse(element("home.tasks.composer", in: app).exists)
    }

    func testCareerActionScenarioShowsCanonicalDetailHierarchy() {
        let app = XCUIApplication()
        app.launchArguments = ["-TAISAPreviewScenario", "actions.action"]
        app.launch()

        let detail = element("career-work.action.detail", in: app)
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Outline first case study"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Checklist"].exists)
        let evidence = element("career-work.action.evidence", in: app)
        let history = element("career-work.action.history", in: app)
        for _ in 0..<4 where !evidence.exists || !history.exists { detail.swipeUp() }
        XCTAssertTrue(evidence.waitForExistence(timeout: 5))
        XCTAssertTrue(history.waitForExistence(timeout: 5))
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
