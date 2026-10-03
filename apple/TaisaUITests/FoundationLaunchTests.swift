import XCTest

final class FoundationLaunchTests: XCTestCase {
    func testFoundationRootLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.otherElements["foundation.root"].waitForExistence(timeout: 5))
    }
}
