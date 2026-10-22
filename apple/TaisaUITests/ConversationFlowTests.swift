import XCTest

@MainActor
final class ConversationFlowTests: XCTestCase {
    func testExistingConversationStaysAtLatestAfterResponseMetadataLoads() {
        let app = XCUIApplication()
        app.launchArguments = ["--taisa-conversation-overflow-qa"]
        app.launch()

        let proposalAction = app.buttons["Add"]
        XCTAssertTrue(proposalAction.waitForExistence(timeout: 5))
        let timeline = app.scrollViews["conversation.timeline"]
        XCTAssertGreaterThanOrEqual(proposalAction.frame.minY, timeline.frame.minY)
        XCTAssertLessThanOrEqual(proposalAction.frame.maxY, timeline.frame.maxY)
    }

    func testVoiceEntryReplacesGlobalDockWithConversationSurface() {
        let app = XCUIApplication()
        app.launch()

        let voice = app.buttons["Talk to Taisa, starts recording"]
        XCTAssertTrue(voice.waitForExistence(timeout: 5))
        voice.tap()

        XCTAssertTrue(element("conversation.root", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("app-shell.conversation-dock", in: app).exists)
        XCTAssertFalse(element("app-shell.primary-navigation", in: app).exists)
        XCTAssertFalse(app.staticTexts["Preparing microphone"].exists)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

}
