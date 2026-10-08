import XCTest

@MainActor final class PersonalRecoveryUITests: XCTestCase {
    func testExplicitQALaunchExposesVoiceDiagnosticsEntry() {
        let app = XCUIApplication()
        app.launchArguments = ["--taisa-personal-device-qa"]
        app.launch()

        let qa = app.buttons["foundation.personal-qa.action"]
        XCTAssertTrue(qa.waitForExistence(timeout: 10))
        qa.tap()
        XCTAssertTrue(
            app.buttons["personal-qa.voice"].waitForExistence(timeout: 10)
        )
    }

    func testPriorWeekReviewStaysPresented() {
        let app = XCUIApplication()
        app.launchArguments = ["--taisa-personal-device-qa"]
        app.launch()

        let qa = app.buttons["foundation.personal-qa.action"]
        XCTAssertTrue(qa.waitForExistence(timeout: 10))
        qa.tap()

        let combinedHome = app.buttons["personal-qa.combined-home.action"]
        XCTAssertTrue(combinedHome.waitForExistence(timeout: 10))
        combinedHome.tap()

        let review = app.buttons["Review 2 unfinished items"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        review.tap()

        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 2))
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "presentation stability interval")], timeout: 2)
        XCTAssertTrue(done.exists)
        XCTAssertTrue(done.isHittable)
    }

    func testExplicitQALaunchCanCreateOnceAndInspectAfterRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--taisa-personal-device-qa"]
        app.launch()
        let qa = app.buttons["foundation.personal-qa.action"]
        XCTAssertTrue(qa.waitForExistence(timeout: 10))
        guard qa.exists else { return }
        qa.tap()
        let presence = app.staticTexts["personal-qa.presence"]
        XCTAssertTrue(presence.waitForExistence(timeout: 10))
        app.buttons["personal-qa.create"].tap()
        let expected = NSPredicate(format: "label == %@", "Canary: present and verified")
        expectation(for: expected, evaluatedWith: presence)
        waitForExpectations(timeout: 10)
        let hash = app.staticTexts["personal-qa.hash"].label
        let counts = app.staticTexts["personal-qa.counts"].label
        app.buttons["personal-qa.create"].tap()
        XCTAssertEqual(app.staticTexts["personal-qa.hash"].label, hash)
        app.terminate()
        app.launch()
        app.buttons["foundation.personal-qa.action"].tap()
        XCTAssertTrue(presence.waitForExistence(timeout: 10))
        XCTAssertEqual(presence.label, "Canary: present and verified")
        XCTAssertEqual(app.staticTexts["personal-qa.hash"].label, hash)
        XCTAssertEqual(app.staticTexts["personal-qa.counts"].label, counts)
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["foundation.recovery.action"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["foundation.personal-qa.action"].exists)
        XCTAssertFalse(app.staticTexts["personal-qa.presence"].exists)
    }

    func testRecoveryActionsAndCancelledFileSelection() throws {
        let app = XCUIApplication()
        app.launch()
        let action = app.buttons["foundation.recovery.action"]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        action.tap()
        XCTAssertTrue(app.staticTexts["Stored securely on this device"].exists)
        XCTAssertTrue(app.buttons["Back Up Now"].isHittable)
        XCTAssertTrue(app.buttons["Restore Backup"].isHittable)
        XCTAssertFalse(app.buttons["Export Encrypted Backup"].exists)
        app.buttons["Restore Backup"].tap()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 15))
        cancel.tap()
        XCTAssertTrue(app.buttons["Back Up Now"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "personal-recovery"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testLargestTypeAndBackgroundReturn() {
        let app = XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.buttons["foundation.recovery.action"].tap()
        for _ in 0..<6 where !app.buttons["Restore Backup"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["Restore Backup"].isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "recovery-largest-type"; attachment.lifetime = .keepAlways; add(attachment)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["Restore Backup"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.secureTextFields["Recovery key"].exists)
    }

    func testConfiguredGatewayRequiresSecureEnrollmentBeforeRecording() {
        let app = XCUIApplication()
        app.launchArguments = ["--taisa-personal-device-qa", "--taisa-voice-gateway-unenrolled"]
        app.launchEnvironment["TAISA_UI_TEST_VOICE_GATEWAY_URL"] = "https://voice.example.com"
        app.launch()
        app.buttons["foundation.personal-qa.action"].tap()
        app.buttons["personal-qa.voice"].tap()

        XCTAssertTrue(app.secureTextFields["Enrollment code"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Connect this device"].exists)
        XCTAssertFalse(app.buttons["Record"].exists)

        app.terminate()
        app.launchArguments = ["--taisa-personal-device-qa", "--taisa-voice-gateway-ready"]
        app.launch()
        app.buttons["foundation.personal-qa.action"].tap()
        app.buttons["personal-qa.voice"].tap()
        XCTAssertTrue(app.buttons["Record"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.secureTextFields["Enrollment code"].exists)
    }
}
