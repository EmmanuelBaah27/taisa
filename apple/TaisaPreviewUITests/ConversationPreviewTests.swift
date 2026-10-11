import XCTest

@MainActor
final class ConversationPreviewTests: XCTestCase {
    func testEveryConversationStateOpensDeterministicallyWithoutProductionRuntime() {
        let identifiers = [
            "conversation-list.empty", "conversation-list.multiple-drafts",
            "conversation-list.recovered-draft", "conversation-list.completed-history",
            "conversation.recording", "conversation.paused", "conversation.typing",
            "conversation.transcribing", "conversation.coaching", "conversation.waiting",
            "conversation.permission-denied", "conversation.retry-transcription",
            "conversation.retry-coaching", "conversation.correction",
            "conversation.accessibility-xxxl", "conversation.ipad",
        ]

        for identifier in identifiers {
            let app = XCUIApplication()
            app.launchArguments = ["-TAISAPreviewScenario", identifier]
            app.launch()
            XCTAssertTrue(
                app.descendants(matching: .any)["preview.ready.\(identifier)"].waitForExistence(timeout: 5),
                identifier
            )
            XCTAssertFalse(app.staticTexts["Conversation unavailable"].exists, identifier)
            app.terminate()
        }
    }
}
