import XCTest
@testable import Taisa

@MainActor
final class PrimaryAppShellTests: XCTestCase {
    func testConversationDestinationUsesChatsAsItsUserFacingName() {
        XCTAssertEqual(PrimaryDestination.conversations.title, "Chats")
    }

    func testPrimaryDestinationSelectionRecordsHorizontalTravelDirection() {
        let model = PrimaryAppShellModel(selection: .home)

        model.select(.conversations)
        XCTAssertEqual(model.navigationDirection, .forward)

        model.select(.home)
        XCTAssertEqual(model.navigationDirection, .backward)
    }

    func testCareerWorkStaysInsideHomeWithoutLeavingThePrimaryPager() {
        let model = PrimaryAppShellModel(selection: .conversations)

        model.showCareerWork()

        XCTAssertEqual(model.selection, .home)
        XCTAssertTrue(model.showsCareerWork)

        model.select(.conversations)
        XCTAssertFalse(model.showsCareerWork)
    }

    func testAdjacentPagingCoversEveryDestinationInBothDirections() {
        let model = PrimaryAppShellModel(selection: .home)

        model.selectAdjacent(offset: 1)
        XCTAssertEqual(model.selection, .conversations)
        model.selectAdjacent(offset: 1)
        XCTAssertEqual(model.selection, .you)
        model.selectAdjacent(offset: 1)
        XCTAssertEqual(model.selection, .you)

        model.selectAdjacent(offset: -1)
        XCTAssertEqual(model.selection, .conversations)
        model.selectAdjacent(offset: -1)
        XCTAssertEqual(model.selection, .home)
        model.selectAdjacent(offset: -1)
        XCTAssertEqual(model.selection, .home)
    }

    func testPrimaryNavigationMatchesTheThreeDestinationProductArchitecture() {
        XCTAssertEqual(PrimaryDestination.allCases, [.home, .conversations, .you])
    }

    func testConversationDismissalRefreshesTheConversationIndex() async {
        let model = PrimaryAppShellModel()
        model.presentNewConversation(.voice)
        var refreshCount = 0

        await model.dismissConversationAndRefresh { refreshCount += 1 }

        XCTAssertNil(model.conversationRoute)
        XCTAssertEqual(refreshCount, 1)
    }

    func testGlobalDockAppearsOnEveryPrimaryDestinationButNotInsideConversation() {
        let model = PrimaryAppShellModel()

        for destination in PrimaryDestination.allCases {
            model.select(destination)
            XCTAssertTrue(model.showsConversationDock)
        }

        model.presentNewConversation(.voice)
        XCTAssertFalse(model.showsConversationDock)
    }

    func testPagesSupportInteractiveHorizontalPagingAndFastNavigation() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("TaisaApp/AppShell/PrimaryAppShell.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("TabView(selection:"))
        XCTAssertTrue(source.contains(".tabViewStyle(.page(indexDisplayMode: .never))"))
        XCTAssertTrue(source.contains("model.select(destination)"))
        XCTAssertFalse(source.contains("if model.selection == .careerWork"))
        XCTAssertTrue(source.contains("model.showsCareerWork"))
        XCTAssertTrue(source.contains("PageEdgeFade(.navigation)"))
        XCTAssertTrue(source.contains(".frame(height: 104)"))
        XCTAssertTrue(source.contains(".safeAreaPadding(.bottom, TaisaControlMetric.primaryNavigationReservedHeight)"))
        XCTAssertFalse(source.contains(".background {\n                    PageEdgeFade(.navigation)"))
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
