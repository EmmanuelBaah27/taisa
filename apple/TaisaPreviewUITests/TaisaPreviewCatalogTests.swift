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
