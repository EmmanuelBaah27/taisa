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
            app.buttons["foundation.voice-diagnostics.action"].waitForExistence(timeout: 10)
        )
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
}
