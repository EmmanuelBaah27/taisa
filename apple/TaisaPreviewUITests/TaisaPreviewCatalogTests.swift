import XCTest

@MainActor
final class TaisaPreviewCatalogTests: XCTestCase {
    func testSharedButtonFoundationPreservesRecordFloatingAndDialogActions() {
        let app = XCUIApplication()
        app.launchArguments = ["-TAISAPreviewScenario", "foundation.buttons"]
        app.launch()
        XCTAssertTrue(app.buttons["buttons.record"].waitForExistence(timeout: 10))
        app.buttons["buttons.record"].tap()
        app.buttons["buttons.primary"].tap()
        app.buttons["buttons.secondary"].tap()
        app.buttons["buttons.header"].tap()
        app.buttons["buttons.floating"].tap()
        XCTAssertFalse(app.buttons["buttons.processing"].isEnabled)
        XCTAssertEqual(app.staticTexts["buttons.counts"].label, "Record 1, actions 3, floating 1, confirmed 0")
        retainScreenshot(of: app, name: "shared-native-button-foundation")
        app.buttons["buttons.destructive"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertEqual(app.staticTexts["buttons.counts"].label, "Record 1, actions 3, floating 1, confirmed 0")
        app.buttons["buttons.destructive"].tap()
        XCTAssertTrue(app.buttons["Confirm preview action"].waitForExistence(timeout: 5))
        app.buttons["Confirm preview action"].tap()
        XCTAssertEqual(app.staticTexts["buttons.counts"].label, "Record 1, actions 3, floating 1, confirmed 1")
    }

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

    func testYouRecoveryActionUsesOneNavigationHeaderAndRemainsReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["-TAISAPreviewScenario", "you.content"]
        app.launch()
        assertRecoveryEntry(in: app)
    }

    func testCatalogYouRecoveryActionUsesOneNavigationHeaderAndRemainsReachable() {
        let app = XCUIApplication()
        app.launch()
        let search = app.searchFields["Search scenarios"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("you.content")
        let scenario = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "You content")).firstMatch
        XCTAssertTrue(scenario.waitForExistence(timeout: 5))
        scenario.tap()
        assertRecoveryEntry(in: app)
    }

    private func assertRecoveryEntry(in app: XCUIApplication) {
        let destination = app.buttons["you.destination.backupRecovery"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        destination.tap()
        let action = app.buttons["Open backup and recovery"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertTrue(action.isHittable)
        // Accessibility coordinate conversion can report 48 as 47.99999999999997.
        XCTAssertGreaterThanOrEqual(action.frame.height, 48 - 0.001)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Back")).count, 1)
        XCTAssertEqual(app.navigationBars.buttons.count, 0, "The catalog must not add a native back control above the DS header")
        retainScreenshot(of: app, name: "you-recovery-glass-action")
        action.tap()
        XCTAssertTrue(app.staticTexts["This preview route composes the existing secure recovery flow."].waitForExistence(timeout: 5))
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
