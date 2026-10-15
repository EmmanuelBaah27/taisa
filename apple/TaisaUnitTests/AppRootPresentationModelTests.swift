import XCTest
@testable import Taisa

@MainActor
final class AppRootPresentationModelTests: XCTestCase {
    func testUserInitiatedRecoveryPresentationDoesNotMutateRuntimeHealth() {
        let model = AppRootPresentationModel()

        model.openUserRecovery()

        XCTAssertTrue(model.showsUserRecovery)
        model.closeUserRecovery()
        XCTAssertFalse(model.showsUserRecovery)
    }
}
