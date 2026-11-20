import XCTest

@MainActor
final class TaisaLaunchTests: XCTestCase {
    func testProductionDevelopmentShellLaunchesHomeWithoutPreviewCatalog() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(element("home.root", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Home"].exists)
        XCTAssertTrue(element("app-shell.primary-navigation", in: app).exists)
        XCTAssertTrue(element("app-shell.conversation-dock", in: app).exists)
        XCTAssertFalse(element("preview.catalog", in: app).exists)
        XCTAssertFalse(element("foundation.diagnostics", in: app).exists)
        retainScreenshot(of: app, name: "development-home")
    }

    func testPrimaryPagerSwipesBothDirectionsAndNavigationTargetsAreComfortablyHittable() {
        let app = XCUIApplication()
        app.launchArguments = ["--taisa-chats-visual-qa"]
        app.launch()

        let chats = element("conversations.root", in: app)
        XCTAssertTrue(chats.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForSelection("Chats", in: app))
        XCTAssertEqual(element("taisa.page-title", in: app).label, "Chats")

        swipeRight(in: app)
        XCTAssertTrue(waitForSelection("Home", in: app))

        swipeLeft(in: app)
        XCTAssertTrue(waitForSelection("Chats", in: app))
        swipeLeft(in: app)
        XCTAssertTrue(waitForSelection("You", in: app))

        swipeRight(in: app)
        XCTAssertTrue(waitForSelection("Chats", in: app))

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

    func testTaskComposerStartsClosedAndStaysAbovePrimaryNavigation() {
        let app = XCUIApplication()
        app.launch()

        let taskTitle = app.textFields["Task title"]
        XCTAssertFalse(taskTitle.exists)

        let addTask = app.buttons["Add task"]
        XCTAssertTrue(addTask.waitForExistence(timeout: 5))
        addTask.tap()

        XCTAssertTrue(taskTitle.waitForExistence(timeout: 2))
        let navigation = app.buttons["Home"]
        XCTAssertTrue(navigation.exists)
        XCTAssertLessThanOrEqual(taskTitle.frame.maxY, navigation.frame.minY)
    }

    func testViewAllTasksPushesTheTasksDestinationAndBackReturnsHome() {
        let app = XCUIApplication()
        app.launch()

        createTaskFromHome("Navigation seed", in: app)
        let viewAll = app.buttons.matching(NSPredicate(format: "label CONTAINS 'View all tasks'")).firstMatch
        XCTAssertTrue(viewAll.waitForExistence(timeout: 5))
        viewAll.tap()

        XCTAssertTrue(element("tasks.root", in: app).waitForExistence(timeout: 2))
        XCTAssertFalse(element("actions.root", in: app).exists)
        let back = app.navigationBars["Tasks"].buttons["Back"]
        XCTAssertTrue(back.exists)
        back.tap()
        XCTAssertTrue(element("home.root", in: app).waitForExistence(timeout: 2))
    }

    func testTasksCreationUsesTheSharedTaskFormAndShowsTheSavedTask() {
        let app = XCUIApplication()
        app.launch()

        createTaskFromHome("Shared form seed", in: app)
        let viewAll = app.buttons.matching(NSPredicate(format: "label CONTAINS 'View all tasks'")).firstMatch
        XCTAssertTrue(viewAll.waitForExistence(timeout: 5))
        viewAll.tap()

        let create = app.buttons["Create task"]
        XCTAssertTrue(create.waitForExistence(timeout: 2))
        create.tap()

        let title = app.textFields["Task title"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        XCTAssertFalse(app.textFields["Details"].exists)
        XCTAssertFalse(app.buttons["Parent"].exists)

        let taskName = "Regression task 941"
        title.typeText(taskName)
        app.buttons["Save task"].tap()

        XCTAssertTrue(app.staticTexts[taskName].waitForExistence(timeout: 3))
        XCTAssertTrue(element("tasks.root", in: app).exists)
        XCTAssertFalse(element("actions.root", in: app).exists)
    }

    func testTaskDueDateCancelReturnsToTheSameSharedForm() {
        let app = XCUIApplication()
        app.launch()

        let addTask = app.buttons["Add task"]
        XCTAssertTrue(addTask.waitForExistence(timeout: 5))
        addTask.tap()

        let due = app.buttons["Due"]
        XCTAssertTrue(due.waitForExistence(timeout: 2))
        due.tap()

        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 2))
        cancel.tap()

        XCTAssertTrue(app.textFields["Task title"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Due"].exists)
        XCTAssertFalse(app.staticTexts["Due date"].exists)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func createTaskFromHome(_ title: String, in app: XCUIApplication) {
        let addTask = app.buttons["Add task"]
        XCTAssertTrue(addTask.waitForExistence(timeout: 5))
        addTask.tap()

        let titleField = app.textFields["Task title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.typeText(title)
        app.buttons["Save task"].tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 3))
    }

    private func waitForSelection(_ label: String, in app: XCUIApplication) -> Bool {
        let selected = NSPredicate(format: "selected == true")
        let expectation = XCTNSPredicateExpectation(predicate: selected, object: app.buttons[label])
        return XCTWaiter.wait(for: [expectation], timeout: 2) == .completed
    }

    private func swipeLeft(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.45))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func swipeRight(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.45))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func retainScreenshot(of app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
