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

    func testProfileEditorUsesTheSharedNeutralInputField() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("TaisaApp/You/YouView.swift"),
            encoding: .utf8
        )
        let profileEditor = try XCTUnwrap(
            source.components(separatedBy: "private struct CareerProfileView").last?
                .components(separatedBy: "private struct PrivacyPermissionsView").first
        )

        XCTAssertTrue(profileEditor.contains("TaisaField(\"Display name\", text: binding(\\.displayName)"))
        XCTAssertTrue(profileEditor.contains("TaisaField(\"Bio\", text: binding(\\.biography), kind: .multiline"))
        XCTAssertTrue(profileEditor.contains("appearance: .profile"))
        XCTAssertNil(profileEditor.range(of: #"(?m)^\s*TextField\("#, options: .regularExpression))
        XCTAssertNil(profileEditor.range(of: #"(?m)^\s*Button\("#, options: .regularExpression))
    }

    func testConversationDestinationUsesChatsAsItsUserFacingName() {
        XCTAssertEqual(PrimaryDestination.conversations.title, "Chats")
    }

    func testWorkDestinationsStayInsideHomeWithoutLeavingThePrimaryPager() {
        let model = PrimaryAppShellModel(selection: .conversations)

        model.showWork(.tasks(route: nil))

        XCTAssertEqual(model.selection, .home)
        XCTAssertEqual(model.workDestination, .tasks(route: nil))

        model.select(.conversations)
        XCTAssertNil(model.workDestination)
    }

    func testWorkDestinationsPreserveExactActionAndGoalIntent() {
        let model = PrimaryAppShellModel()

        model.showWork(.tasks(route: .action(id: "action-1")))
        XCTAssertEqual(model.workDestination, .tasks(route: .action(id: "action-1")))

        model.showWork(.goals(route: .goal(id: "goal-1")))
        XCTAssertEqual(model.workDestination, .goals(route: .goal(id: "goal-1")))
    }

    func testHomeTaskPresentationStaysSeparateFromWorkNavigation() {
        let model = PrimaryAppShellModel()

        model.presentTask(id: "task-1")

        XCTAssertEqual(model.selectedTaskID, "task-1")
        XCTAssertNil(model.workDestination)

        model.dismissTask()
        XCTAssertNil(model.selectedTaskID)
    }

    func testLegacyCareerWorkRestorationRedirectsByIntent() {
        XCTAssertEqual(WorkDestination.restoringLegacyCareerWork(routeStableID: "action:a1"), .tasks(route: .action(id: "a1")))
        XCTAssertEqual(WorkDestination.restoringLegacyCareerWork(routeStableID: "goal:g1"), .goals(route: .goal(id: "g1")))
        XCTAssertEqual(WorkDestination.restoringLegacyCareerWork(routeStableID: "milestone:g1"), .goals(route: .goal(id: "g1")))
        XCTAssertEqual(WorkDestination.restoringLegacyCareerWork(routeStableID: "evidence:e1"), .goals(route: .evidence(id: "e1")))
        XCTAssertEqual(WorkDestination.restoringLegacyCareerWork(routeStableID: nil), .tasks(route: nil))
    }

    func testPrimaryNavigationMatchesTheThreeDestinationProductArchitecture() {
        XCTAssertEqual(PrimaryDestination.allCases, [.home, .conversations, .you])
    }

    func testAdjacentPagingClampsAtBothEnds() {
        let model = PrimaryAppShellModel(selection: .home)

        model.selectAdjacent(offset: -1)
        XCTAssertEqual(model.selection, .home)
        model.selectAdjacent(offset: 1)
        XCTAssertEqual(model.selection, .conversations)
        model.selectAdjacent(offset: 1)
        XCTAssertEqual(model.selection, .you)
        model.selectAdjacent(offset: 1)
        XCTAssertEqual(model.selection, .you)
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

    func testPrimaryDestinationsRemainMountedInTheNativePager() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("TaisaApp/AppShell/PrimaryAppShell.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("TabView(selection:"))
        XCTAssertTrue(source.contains(".tabViewStyle(.page(indexDisplayMode: .never))"))
        XCTAssertTrue(source.contains(".simultaneousGesture(primaryPageCompletionGesture)"))
        XCTAssertFalse(source.contains("if model.selection == .careerWork"))
        XCTAssertTrue(source.contains("model.workDestination"))
        XCTAssertTrue(source.contains("TasksView("))
        XCTAssertFalse(source.contains("ActionsView("))
        XCTAssertTrue(source.contains("GoalsView("))
        XCTAssertFalse(source.contains("CareerWorkView("))
        XCTAssertTrue(source.contains(".safeAreaInset(edge: .bottom, spacing: 0)"))
        XCTAssertTrue(source.contains("TaisaBottomChrome"))
        XCTAssertFalse(source.contains("PageEdgeFade(.navigation)"))
        XCTAssertFalse(source.contains(".frame(height: 104)"))
        XCTAssertFalse(source.contains("primaryPageBottomReservation"))
        XCTAssertFalse(source.contains("selection == .conversations ? 0"))
        XCTAssertFalse(source.contains(".background {\n                    PageEdgeFade(.navigation)"))
        XCTAssertTrue(source.contains("TaisaExpandableSheet"))
        XCTAssertTrue(source.contains("TaskDetailSheetContent("))
        XCTAssertTrue(source.contains("taskChanged: { Task { await homeModel.load() } }"))
        XCTAssertTrue(source.contains("careerWorkModel.returnToOverview()"))
        XCTAssertTrue(source.contains("case let .action(id): model.presentTask(id: id)"))
        XCTAssertTrue(source.contains("case .actions:"))
        XCTAssertTrue(source.contains("model.showWork(.tasks(route: nil))"))
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
