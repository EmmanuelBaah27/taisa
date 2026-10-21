import XCTest

@MainActor
final class ConversationPreviewTests: XCTestCase {
    func testResponseFeedbackFactorsOpenInADismissibleSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["-TAISAPreviewScenario", "conversation.senior-self-response"]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["preview.ready.conversation.senior-self-response"]
                .waitForExistence(timeout: 5)
        )

        let notHelpful = app.descendants(matching: .any)["conversation.feedback.not_helpful"]
        XCTAssertTrue(notHelpful.waitForExistence(timeout: 5))
        notHelpful.tap()

        let factors = app.descendants(matching: .any)["conversation.feedback-factors"]
        let close = app.buttons["conversation.feedback.close"]
        let save = app.buttons["conversation.feedback.save"]
        let detail = app.descendants(matching: .any)["conversation.feedback.detail"]
        XCTAssertTrue(factors.waitForExistence(timeout: 5))
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        close.tap()

        XCTAssertFalse(factors.waitForExistence(timeout: 1))
        XCTAssertTrue(notHelpful.exists)

        notHelpful.tap()
        XCTAssertTrue(factors.waitForExistence(timeout: 5))

        let remove = app.buttons["conversation.feedback.remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertFalse(factors.waitForExistence(timeout: 1))

        notHelpful.tap()
        XCTAssertTrue(factors.waitForExistence(timeout: 5))
    }

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
