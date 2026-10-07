import XCTest

@MainActor
final class VoiceSessionAccessibilityTests: XCTestCase {
    func testAccessibilityTextPreservesChronologicalActionsAndTextStatus() {
        let app = XCUIApplication()
        app.launchArguments = ["-TAISAPreviewScenario", "voice.accessibility"]
        app.launch()

        let root = app.descendants(matching: .any)["voice.diagnostics.root"]
        XCTAssertTrue(root.waitForExistence(timeout: 5))

        let status = app.staticTexts["voice.diagnostics.status"]
        let pause = app.buttons["voice.action.pause"]
        let send = app.buttons["voice.action.send"]
        let cancel = app.buttons["voice.action.cancel"]
        let discard = app.buttons["voice.action.discard"]
        XCTAssertTrue(status.exists)
        XCTAssertTrue(pause.isHittable)
        XCTAssertTrue(send.isHittable)
        XCTAssertTrue(cancel.isHittable)
        XCTAssertTrue(discard.isHittable)
        XCTAssertLessThan(status.frame.minY, pause.frame.minY)
        XCTAssertLessThan(pause.frame.minY, send.frame.minY)
        XCTAssertLessThan(send.frame.minY, cancel.frame.minY)
        XCTAssertLessThan(cancel.frame.minY, discard.frame.minY)
    }

    func testReducedMotionScenarioExposesStaticWaveform() {
        let app = XCUIApplication()
        app.launchArguments = ["-TAISAPreviewScenario", "voice.reducedMotion"]
        app.launch()

        let waveform = app.otherElements["voice.waveform.static"]
        XCTAssertTrue(waveform.waitForExistence(timeout: 5))
    }
}
