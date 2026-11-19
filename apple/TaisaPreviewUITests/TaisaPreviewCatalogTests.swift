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
