import XCTest

@MainActor
final class ConversationFlowTests: XCTestCase {
    func testVoiceEntryReplacesGlobalDockWithConversationSurface() {
        let app = XCUIApplication()
        app.launch()

        let voice = app.buttons["Talk to Taisa, starts recording"]
        XCTAssertTrue(voice.waitForExistence(timeout: 5))
        voice.tap()

        XCTAssertTrue(element("conversation.root", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("app-shell.conversation-dock", in: app).exists)
        XCTAssertFalse(element("app-shell.primary-navigation", in: app).exists)
    }

    func testKeyboardEntryUsesTheSameSingleConversationRoute() {
        let app = XCUIApplication()
        app.launch()

        let keyboard = app.buttons["Talk to Taisa with keyboard"]
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        keyboard.tap()

        XCTAssertTrue(element("conversation.root", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("app-shell.conversation-dock", in: app).exists)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
