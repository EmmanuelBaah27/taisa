import XCTest

@MainActor
final class ConversationPreviewTests: XCTestCase {
    func testExistingConversationOpensAtLatestAndJumpReturnsToLatest() {
        let app = XCUIApplication()
        app.launchArguments = ["-TAISAPreviewScenario", "conversation.existing-history"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["preview.ready.conversation.existing-history"].waitForExistence(timeout: 5))
        let latest = app.staticTexts["Latest rendered conversation message"]
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        XCTAssertTrue(latest.isHittable)

        let timeline = app.scrollViews["conversation.root"]
        timeline.swipeDown()
        let jump = app.buttons["Jump to latest response"]
        XCTAssertTrue(jump.waitForExistence(timeout: 3))
        jump.tap()

        XCTAssertTrue(latest.waitForExistence(timeout: 3))
        XCTAssertTrue(latest.isHittable)
        XCTAssertFalse(jump.waitForExistence(timeout: 1))
    }

    func testSentMessageAnchorsNearTopBeforeResponseArrives() {
        let app = XCUIApplication()
        app.launchArguments = ["-TAISAPreviewScenario", "conversation.sent-turn-anchor"]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["preview.ready.conversation.sent-turn-anchor"]
                .waitForExistence(timeout: 5)
        )

        let send = app.buttons["Send message"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()

        let sentMessage = app.descendants(matching: .any)["conversation.message.sent-turn-anchor"]
        XCTAssertTrue(sentMessage.waitForExistence(timeout: 5))
        XCTAssertLessThan(sentMessage.frame.minY, app.frame.height * 0.35)
    }

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
        XCTAssertTrue(factors.waitForExistence(timeout: 5))
        XCTAssertTrue(close.waitForExistence(timeout: 5))
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
            "conversation.existing-history",
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
