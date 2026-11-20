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

    func testCombinedHomeUsesApprovedTasksOnlySurface() {
        let app = XCUIApplication()
        app.launchArguments = ["-TAISAPreviewScenario", "home.combined"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Tasks this week"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Measure the north wall"].exists)
        XCTAssertFalse(app.staticTexts["Your best planning sessions happen before midday."].exists)
        XCTAssertFalse(element("home.lead-insight", in: app).exists)
    }

    func testCombinedHomeRoutesCurrentFocusWithoutCompletionManagement() {
        let app = XCUIApplication()
        app.launchArguments = ["-TAISAPreviewScenario", "home.combined"]
        app.launch()

        let action = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Measure the north wall")).firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertTrue(action.isHittable)
        XCTAssertFalse(app.buttons["Complete Measure the north wall"].exists)
        XCTAssertFalse(element("home.this-week.completion-evidence", in: app).exists)
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

    func testRedesignedYouContentKeepsCatalogBackNavigation() {
        let app = XCUIApplication()
        app.launch()

        let search = app.searchFields["Search scenarios"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("you.content")

        let row = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "You content")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        XCTAssertTrue(app.staticTexts["Baah"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Product designer at Oyster"].exists)
        XCTAssertTrue(element("you.profile.edit", in: app).exists)

        let back = app.buttons["Taisa Preview"]
        if back.waitForExistence(timeout: 2) {
            back.tap()
            XCTAssertTrue(search.waitForExistence(timeout: 5))
        } else {
            XCTAssertTrue(app.buttons["Hide Sidebar"].waitForExistence(timeout: 5))
        }
    }

    func testYouScenarioReusesCatalogNavigationOwner() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("TaisaPreview/YouScenarioView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(
            source.contains("NavigationStack {\n            YouView("),
            "The You preview scenario must reuse PreviewCatalogView navigation."
        )
    }

    func testYouDestinationReturnRestoresCatalogNavigation() {
        let app = XCUIApplication()
        app.launch()

        let search = app.searchFields["Search scenarios"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("you.content")

        let row = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "You content")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let privacy = element("you.destination.privacyPermissions", in: app)
        XCTAssertTrue(privacy.waitForExistence(timeout: 5))
        privacy.tap()

        let destinationBack = app.buttons["Back"]
        XCTAssertTrue(destinationBack.waitForExistence(timeout: 5))
        destinationBack.tap()

        XCTAssertTrue(app.buttons["Taisa Preview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["You content"].exists)
    }

    func testYouEditorExplainsInvalidNameAndCanCloseWithoutLosingDraft() {
        let app = XCUIApplication()
        app.launchArguments = ["-TAISAPreviewScenario", "you.content"]
        app.launch()

        let edit = element("you.profile.edit", in: app)
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()

        let name = app.textFields["Display name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(String(repeating: "x", count: 81))
        XCTAssertTrue(app.staticTexts["Display name must be 80 characters or fewer."].waitForExistence(timeout: 5))

        element("you.profile.close", in: app).tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertEqual(app.textFields["Display name"].value as? String, "Baah" + String(repeating: "x", count: 81))
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
