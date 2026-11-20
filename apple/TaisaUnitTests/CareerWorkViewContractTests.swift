import Foundation
import XCTest
import TaisaCareerWork
import TaisaStorage
@testable import Taisa

@MainActor
final class TaskDetailPresentationTests: XCTestCase {
    func testRetainedDetailForAnotherTaskStaysLoading() {
        let detail = taskDetail(id: "task-a")
        let state = CareerWorkState.content(snapshot(detail: detail), isRefreshing: true, issue: nil)

        XCTAssertEqual(TaskDetailPresentation.resolve(state, actionID: "task-b"), .loading)
    }

    func testCurrentFailureWinsOverRetainedDetail() {
        let detail = taskDetail(id: "task-a")
        let state = CareerWorkState.content(snapshot(detail: detail), isRefreshing: false, issue: .recoveryRequired)

        XCTAssertEqual(TaskDetailPresentation.resolve(state, actionID: "task-b"), .failure(.recoveryRequired))
    }

    func testMatchingDetailIsPresentedAfterSuccessfulLoad() {
        let detail = taskDetail(id: "task-b")
        let state = CareerWorkState.content(snapshot(detail: detail), isRefreshing: false, issue: nil)

        guard case let .detail(resolved, _) = TaskDetailPresentation.resolve(state, actionID: "task-b") else {
            return XCTFail("Expected matching task detail")
        }
        XCTAssertEqual(resolved, detail)
    }

    private func taskDetail(id: String) -> ActionDetailSnapshot {
        let action = ActionRecord(id: id, goalID: nil, title: id, detail: "", status: "active", dueAtMS: nil, createdAtMS: 1, updatedAtMS: 1)
        return ActionDetailSnapshot(action: action, goal: nil, milestone: nil, checklist: [], events: [], currentEvidence: [], supersededEvidence: [], placement: nil)
    }

    private func snapshot(detail: ActionDetailSnapshot) -> CareerWorkProductSnapshot {
        CareerWorkProductSnapshot(
            overview: .init(active: [], paused: [], completed: [], archived: []),
            selectedGoal: nil,
            selectedAction: detail.action,
            selectedActionDetail: detail
        )
    }
}

final class CareerWorkViewContractTests: XCTestCase {
    func testJourneyUsesAdaptiveNativeNavigationAndExplicitStates() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("TaisaApp/CareerWork/CareerWorkView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("NavigationSplitView"))
        XCTAssertTrue(source.contains("NavigationStack"))
        XCTAssertTrue(source.contains("TaisaChildPageHeader(detailTitle"))
        XCTAssertTrue(source.contains("horizontalSizeClass == .regular ? .detail : .back"))
        XCTAssertTrue(source.contains(".safeAreaInset(edge: .top, spacing: 0)"))
        XCTAssertTrue(source.contains("tasks.empty"))
        XCTAssertTrue(source.contains("goals.empty"))
        XCTAssertTrue(source.contains("career-work.retry"))
        XCTAssertTrue(source.contains("career-work.recovery"))
        XCTAssertTrue(source.contains("accessibilityLabel"))
        XCTAssertTrue(source.contains("career-work.proposal.review"))
        XCTAssertTrue(source.contains("Origin:"))
        XCTAssertTrue(source.contains("Add milestone"))
        XCTAssertTrue(source.contains("Add task"))
        XCTAssertTrue(source.contains("Add evidence"))
        XCTAssertTrue(source.contains("tasks.collection"))
        XCTAssertTrue(source.contains("tasks.create"))
        XCTAssertTrue(source.contains("tasks.editor"))
        XCTAssertTrue(source.contains("career-work.action.duplicate-review"))
        XCTAssertTrue(source.contains("career-work.action.checklist"))
        XCTAssertTrue(source.contains("career-work.action.history"))
        XCTAssertTrue(source.contains("career-work.action.evidence"))
        XCTAssertTrue(source.contains("career-work.action.delete"))
        XCTAssertTrue(source.contains("career-work.action.restore"))
        XCTAssertTrue(source.contains("career-work.action.parent-goal"))
        XCTAssertTrue(source.contains("career-work.action.parent-milestone"))
        XCTAssertTrue(source.contains("open(.goal(id: goal.id))"))
        XCTAssertTrue(source.contains("open(.goal(id: milestone.goalID))"))
        XCTAssertTrue(source.contains("open(.evidence(id: evidence.id))"))
        XCTAssertTrue(source.contains("tasks.filters"))
        XCTAssertTrue(source.contains("career-work.action.filter-sheet"))
        XCTAssertTrue(source.contains("Correct mistaken completion"))
        XCTAssertTrue(source.contains("allMilestones"))
        XCTAssertTrue(source.contains("WeekCalendar(timeZone: .current)"))
        XCTAssertTrue(source.contains("parent: .goal(id: goal.goal.id)"))
        XCTAssertTrue(source.contains("snapshot.action.dueAtMS.map"))
        XCTAssertTrue(source.contains("let saved = await model.editSelectedAction"))
        XCTAssertTrue(source.contains("if await save(draft) { dismiss() }"))
        XCTAssertFalse(source.contains("recentlyDeletedActionID"))
        XCTAssertTrue(source.contains("Parent is inactive"))
        XCTAssertTrue(source.contains("Parent was deleted"))
        XCTAssertTrue(source.contains("TaskComposerView("))
        XCTAssertFalse(source.contains("case .action:"))
        XCTAssertTrue(source.contains("selectedRoute = nil"))
        XCTAssertTrue(source.contains("TaisaPicker("))
        XCTAssertTrue(source.contains("TaisaConfirmationDialog("))
        XCTAssertTrue(source.contains("TaisaStatusSurface("))
        XCTAssertTrue(source.contains("TaisaRow("))
        XCTAssertTrue(source.contains("CentralIcon(.history)"))
        XCTAssertFalse(source.contains("Color("))
        XCTAssertFalse(source.contains("systemImage:"))
        XCTAssertFalse(source.contains(".font("))
        XCTAssertFalse(source.contains(".foregroundStyle("))
        XCTAssertNil(source.range(of: #"(?<!Taisa)TextField\("#, options: .regularExpression))
        XCTAssertNil(source.range(of: #"(?<!Taisa)DatePicker\("#, options: .regularExpression))
        XCTAssertNil(source.range(of: #"(?<!Taisa)Picker\("#, options: .regularExpression))
    }

    func testTaskDetailSheetUsesSharedFigmaDetailAndDismissesOnlyAfterDeletion() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("TaisaApp/CareerWork/CareerWorkView.swift"), encoding: .utf8)
        let detail = source

        XCTAssertTrue(source.contains("struct TaskDetailSheetContent"))
        XCTAssertTrue(source.contains(".task(id: actionID)"))
        XCTAssertTrue(source.contains("await model.select(.action(id: actionID))"))
        XCTAssertTrue(source.contains("TaskDetailSheetView("))
        XCTAssertTrue(detail.contains("TaisaText(role: .sheetTitle"))
        XCTAssertTrue(detail.contains(".padding(.top, TaisaSpacing.control.rawValue)"))
        XCTAssertTrue(detail.contains("TaisaText(role: .sectionLabel"))
        XCTAssertTrue(detail.contains("TaisaText(role: .body"))
        XCTAssertFalse(detail.contains("TaisaColor.subtleSurface.color"))
        XCTAssertTrue(detail.contains("TaisaButton(\n                        role: .ghost"))
        XCTAssertTrue(detail.contains("showsDueDatePicker = true"))
        XCTAssertTrue(detail.contains("TaisaGraphicalDatePickerSheet("))
        XCTAssertTrue(detail.contains("await model.editSelectedAction(draft"))
        XCTAssertTrue(detail.contains("TaisaPressable(action: { isAddingSubtask = true })"))
        XCTAssertTrue(detail.contains("TaisaText(role: .buttonLabel, content: \"Add sub-task\")"))
        XCTAssertTrue(detail.contains("labelPresentation: .placeholderOnly"))
        XCTAssertTrue(detail.contains("TaisaSecondaryCapsuleButton(elevation: .floating)"))
        XCTAssertTrue(detail.contains("TaisaSecondaryCapsuleButton"))
        XCTAssertTrue(detail.contains("TaisaGroupedIconActions"))
        XCTAssertTrue(detail.contains("item.state == .completed ? .completed : .incomplete"))
        XCTAssertTrue(detail.contains("await model.setChecklistItemCompleted"))
        XCTAssertTrue(detail.contains("await model.removeChecklistItem"))
        XCTAssertTrue(detail.contains("await model.addChecklistItem"))
        XCTAssertTrue(detail.contains("await model.completeSelectedAction"))
        XCTAssertTrue(detail.contains("await model.dropSelectedAction"))
        XCTAssertTrue(detail.contains("await model.setSelectedActionBlocked(note: blockerNote)"))
        XCTAssertTrue(detail.contains("await model.clearSelectedActionBlocked()"))
        XCTAssertTrue(detail.contains("TaisaStatusSurface(.warning, label: \"Blocked\")"))
        XCTAssertTrue(detail.contains("if await model.deleteSelectedAction()"))
        XCTAssertTrue(detail.contains("dismiss()"))
        XCTAssertTrue(source.contains("openRecovery()"))
        XCTAssertNil(detail.range(of: #"(?m)^\s*Button\("#, options: .regularExpression))
        XCTAssertFalse(detail.contains("Image(systemName:"))
        XCTAssertFalse(detail.contains("Color("))
        XCTAssertFalse(detail.contains(".font("))
    }

    func testTasksCollectionPresentsTheSharedExpandableDetailSheet() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("TaisaApp/CareerWork/CareerWorkView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("@State private var selectedTaskID: String?"))
        XCTAssertTrue(source.contains("selectedTaskID = action.id"))
        XCTAssertFalse(source.contains("TaisaPressable(action: { selectedRoute = .action(id: action.id) })"))
        XCTAssertTrue(source.contains("TaisaExpandableSheet"))
        XCTAssertTrue(source.contains("TaskDetailSheetContent("))
        XCTAssertTrue(source.contains("onDismiss: refreshTasksAfterTaskDetail"))
        XCTAssertTrue(source.contains("model.returnToOverview()"))
        XCTAssertTrue(source.contains(".task(id: actionID)"), "Changing task identifiers must reload exact detail")
        XCTAssertTrue(source.contains("TaskDetailPresentation.resolve(model.state, actionID: actionID)"))
    }
}
