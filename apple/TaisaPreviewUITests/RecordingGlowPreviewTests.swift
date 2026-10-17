import XCTest

@MainActor
final class RecordingGlowPreviewTests: XCTestCase {
    func testEveryDeterministicGlowScenarioIsRegisteredExactlyOnce() {
        let identifiers = [
            "recording-glow.silent",
            "recording-glow.low",
            "recording-glow.conversational",
            "recording-glow.peak",
            "recording-glow.paused",
            "recording-glow.reduce-motion",
            "recording-glow.reduced-transparency",
            "recording-glow.tuner",
        ]

        for identifier in identifiers {
            let app = XCUIApplication()
            app.launchArguments = ["-TAISAPreviewScenario", identifier]
            app.launch()
            XCTAssertTrue(
                app.descendants(matching: .any)["preview.ready.\(identifier)"]
                    .waitForExistence(timeout: 5),
                identifier
            )
            XCTAssertEqual(
                app.descendants(matching: .any)
                    .matching(identifier: "recording-glow.surface").count,
                1,
                identifier
            )
            app.terminate()
        }
    }

    func testSilentAndPausedRenderingRemainStableAcrossCaptures() {
        for identifier in ["recording-glow.silent", "recording-glow.paused"] {
            let app = XCUIApplication()
            app.launchArguments = ["-TAISAPreviewScenario", identifier]
            app.launch()
            XCTAssertTrue(
                app.descendants(matching: .any)["recording-glow.surface"]
                    .waitForExistence(timeout: 5)
            )
            let surface = app.descendants(matching: .any)["recording-glow.surface"]
            let first = surface.screenshot().pngRepresentation
            let second = surface.screenshot().pngRepresentation
            XCTAssertEqual(first, second, identifier)
            app.terminate()
        }
    }

    func testTunerExposesResetExportPaletteGrainAndGeometryControls() {
        let app = XCUIApplication()
        app.launchArguments = ["-TAISAPreviewScenario", "recording-glow.tuner"]
        app.launch()

        XCTAssertTrue(app.buttons["Reset to Figma preset"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Copy preset JSON"].exists)
        XCTAssertTrue(app.sliders["Simulated loudness"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["Dominant center purple color"].exists
        )
        XCTAssertTrue(app.sliders["Grain amount"].exists)
        XCTAssertTrue(app.sliders["Center peak height"].exists)
        XCTAssertTrue(app.staticTexts["#CBAEFF"].exists)
    }

    func testTunerUsesFullLabelStateChoicesAndOffersLiveMicrophoneInput() {
        let app = XCUIApplication()
        app.launchArguments = ["-TAISAPreviewScenario", "recording-glow.tuner"]
        app.launch()

        XCTAssertTrue(app.buttons["Recording"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Paused"].exists)
        XCTAssertTrue(app.buttons["Reduce motion"].exists)
        XCTAssertTrue(app.buttons["Less transparency"].exists)
        XCTAssertTrue(app.buttons["Simulated"].exists)
        XCTAssertTrue(app.buttons["Live microphone"].exists)
        XCTAssertEqual(app.segmentedControls.count, 0)

        let controls = app.scrollViews["recording-glow.controls"]
        XCTAssertTrue(controls.exists)
        let surface = app.descendants(matching: .any)["recording-glow.surface"]
        let originalSurfaceFrame = surface.frame
        controls.swipeUp()
        XCTAssertEqual(surface.frame, originalSurfaceFrame)
    }

    func testLiveMicrophoneRequestKeepsTunerRunning() {
        let app = XCUIApplication()
        app.launchArguments = ["-TAISAPreviewScenario", "recording-glow.tuner"]
        addUIInterruptionMonitor(withDescription: "Microphone permission") { alert in
            let allow = alert.buttons["Allow"]
            guard allow.exists else { return false }
            allow.tap()
            return true
        }
        app.launch()

        let liveMicrophone = app.buttons["Live microphone"]
        XCTAssertTrue(liveMicrophone.waitForExistence(timeout: 5))
        liveMicrophone.tap()
        app.tap()

        XCTAssertTrue(app.staticTexts["Live level"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["Listening — receiving audio"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }
}
