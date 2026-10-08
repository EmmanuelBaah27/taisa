import XCTest
@testable import Taisa

@MainActor
final class PrimaryAppShellTests: XCTestCase {
    func testGlobalDockAppearsOnEveryPrimaryDestinationButNotInsideConversation() {
        let model = PrimaryAppShellModel()

        for destination in PrimaryDestination.allCases {
            model.select(destination)
            XCTAssertTrue(model.showsConversationDock)
        }

        model.presentNewConversation(.voice)
        XCTAssertFalse(model.showsConversationDock)
    }

    func testVoiceEntryIntentIsConsumedOnlyOnce() {
        let model = PrimaryAppShellModel()
        model.presentNewConversation(.voice)

        XCTAssertEqual(model.consumeEntryIntent(), .voice)
        XCTAssertNil(model.consumeEntryIntent())
        XCTAssertNotNil(model.conversationRoute)
    }

    func testDismissRestoresDockWithoutChangingPrimaryDestination() {
        let model = PrimaryAppShellModel()
        model.select(.conversations)
        model.presentNewConversation(.text)

        model.dismissConversation()

        XCTAssertEqual(model.selection, .conversations)
        XCTAssertNil(model.conversationRoute)
        XCTAssertTrue(model.showsConversationDock)
    }
}
