import XCTest
@testable import Taisa

@MainActor
final class PrimaryAppShellTests: XCTestCase {
    func testYouChildDestinationsUseTheSharedAdaptiveHeaderFade() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("TaisaApp/You/YouView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("TaisaChildPageHeader(destination.title"))
        XCTAssertTrue(source.contains("horizontalSizeClass == .regular ? .detail : .back"))
        XCTAssertTrue(source.contains(".safeAreaInset(edge: .top, spacing: 0)"))
    }

    func testConversationDestinationUsesChatsAsItsUserFacingName() {
        XCTAssertEqual(PrimaryDestination.conversations.title, "Chats")
    }

    func testWorkDestinationsStayInsideHomeWithoutLeavingThePrimaryPager() {
        let model = PrimaryAppShellModel(selection: .conversations)

        model.showWork(.actions(route: nil))

        XCTAssertEqual(model.selection, .home)
        XCTAssertEqual(model.workDestination, .actions(route: nil))

        model.select(.conversations)
        XCTAssertNil(model.workDestination)
    }

    func testWorkDestinationsPreserveExactActionAndGoalIntent() {
        let model = PrimaryAppShellModel()

        model.showWork(.actions(route: .action(id: "action-1")))
        XCTAssertEqual(model.workDestination, .actions(route: .action(id: "action-1")))

        model.showWork(.goals(route: .goal(id: "goal-1")))
        XCTAssertEqual(model.workDestination, .goals(route: .goal(id: "goal-1")))
    }

    func testLegacyCareerWorkRestorationRedirectsByIntent() {
        XCTAssertEqual(WorkDestination.restoringLegacyCareerWork(routeStableID: "action:a1"), .actions(route: .action(id: "a1")))
        XCTAssertEqual(WorkDestination.restoringLegacyCareerWork(routeStableID: "goal:g1"), .goals(route: .goal(id: "g1")))
        XCTAssertEqual(WorkDestination.restoringLegacyCareerWork(routeStableID: "milestone:g1"), .goals(route: .goal(id: "g1")))
        XCTAssertEqual(WorkDestination.restoringLegacyCareerWork(routeStableID: "evidence:e1"), .goals(route: .evidence(id: "e1")))
        XCTAssertEqual(WorkDestination.restoringLegacyCareerWork(routeStableID: nil), .actions(route: nil))
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

    func testPrimaryDestinationsRemainMountedBehindTheCustomNavigation() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("TaisaApp/AppShell/PrimaryAppShell.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("ForEach(PrimaryDestination.allCases"))
        XCTAssertTrue(source.contains("NavigationStack {\n                    destinationView(destination)"))
        XCTAssertTrue(source.contains(".allowsHitTesting(model.selection == destination)"))
        XCTAssertTrue(source.contains(".accessibilityHidden(model.selection != destination)"))
        XCTAssertFalse(source.contains("if model.selection == .careerWork"))
        XCTAssertTrue(source.contains("model.workDestination"))
        XCTAssertTrue(source.contains("ActionsView("))
        XCTAssertTrue(source.contains("GoalsView("))
        XCTAssertFalse(source.contains("CareerWorkView("))
        XCTAssertTrue(source.contains(".safeAreaInset(edge: .bottom, spacing: 0)"))
        XCTAssertTrue(source.contains("TaisaBottomChrome"))
        XCTAssertFalse(source.contains("PageEdgeFade(.navigation)"))
        XCTAssertFalse(source.contains(".frame(height: 104)"))
        XCTAssertFalse(source.contains("primaryPageBottomReservation"))
        XCTAssertFalse(source.contains("selection == .conversations ? 0"))
        XCTAssertFalse(source.contains(".safeAreaPadding(.bottom"))
        XCTAssertFalse(source.contains(".background {\n                    PageEdgeFade(.navigation)"))
    }

    func testVoiceEntryIntentIsConsumedOnlyOnce() {
        let model = PrimaryAppShellModel()
        model.presentNewConversation(.voice)

        XCTAssertEqual(model.consumeEntryIntent(), .voice)
        XCTAssertNil(model.consumeEntryIntent())
        XCTAssertEqual(model.conversationRoute?.localTitle, "New chat")
    }

    func testDismissRestoresDockWithoutChangingPrimaryDestination() {
        let model = PrimaryAppShellModel()
        model.select(.conversations)
        model.presentNewConversation(.text)

        model.dismissConversation()

        XCTAssertEqual(model.selection, .conversations)
        XCTAssertNil(model.conversationRoute)
        XCTAssertTrue(model.showsConversationDock)
        XCTAssertEqual(model.conversationReturnGeneration, 1)
    }

}
