import XCTest

@MainActor final class PersonalRecoveryUITests: XCTestCase {
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
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
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
