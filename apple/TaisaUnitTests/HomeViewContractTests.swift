import Foundation
import XCTest

final class HomeViewContractTests: XCTestCase {
    func testHomeRoutesDirectlyToActionsAndGoalsWithoutCareerWorkSections() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let home = root.appendingPathComponent("TaisaApp/Home")
        let sources = try FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        XCTAssertFalse(sources.contains("Section(\"Upcoming milestones\")"))
        XCTAssertTrue(sources.contains("case actions"))
        XCTAssertTrue(sources.contains("case goals"))
    }

    func testHomeUsesRequiredNativeStateIdentifiersAndNoGRDB() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let home = root.appendingPathComponent("TaisaApp/Home")
        let sources = try FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        for identifier in ["home.root", "home.actions.preview", "home.empty", "home.retry", "home.recovery", "home.tasks.composer"] {
            XCTAssertTrue(sources.contains(identifier), "Missing \(identifier)")
        }
        XCTAssertFalse(sources.contains("import GRDB"))
        XCTAssertTrue(sources.contains("NavigationStack"))
        XCTAssertTrue(sources.contains("ContentUnavailableView"))
        XCTAssertTrue(sources.contains("refreshable"))
    }

    func testHomeUsesTheApprovedTasksOnlyComposition() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let home = root.appendingPathComponent("TaisaApp/Home")
        let homeView = try String(contentsOf: home.appendingPathComponent("HomeView.swift"), encoding: .utf8)
        let thisWeek = try String(contentsOf: home.appendingPathComponent("ThisWeekSection.swift"), encoding: .utf8)
        let leadInsight = try String(contentsOf: home.appendingPathComponent("LeadInsightSection.swift"), encoding: .utf8)

        XCTAssertTrue(homeView.contains("HomeActionsPreviewSection("))
        XCTAssertFalse(homeView.contains("ThisWeekSection("))
        XCTAssertFalse(homeView.contains("HomeGoalsSummarySection("))
        XCTAssertFalse(homeView.contains("LeadInsightSection("))
        XCTAssertFalse(homeView.contains("HomeReviewSection("))

        for identifier in ["home.this-week", "home.prior-week.review", "home.actions.preview", "home.actions.view-all", "home.goals.summary", "home.goals.view-all"] {
            XCTAssertTrue(thisWeek.contains(identifier), "Missing \(identifier)")
        }
        XCTAssertFalse(thisWeek.contains("await model.undoCompletion()"))
        XCTAssertFalse(thisWeek.contains("home.this-week.complete"))
        XCTAssertTrue(thisWeek.contains("TaisaRow("))
        XCTAssertFalse(thisWeek.contains("systemImage:"), "Touched Home Action UI must use Central Icons")
        XCTAssertTrue(leadInsight.contains("home.lead-insight"), "Nested Insights remains implemented even though Home does not expose it in this iteration")
    }

    func testTouchedHomeSurfaceUsesSharedDesignSystemContracts() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let home = root.appendingPathComponent("TaisaApp/Home")
        let sources = try ["HomeView.swift", "HomeSectionViews.swift", "ThisWeekSection.swift", "TaskComposerView.swift"]
            .map { try String(contentsOf: home.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")

        for contract in ["TaisaRow(", "TaisaText(", "TaisaButton(", "TaisaToolbarAction(", "CentralIcon("] {
            XCTAssertTrue(sources.contains(contract), "Missing shared contract \(contract)")
        }
        XCTAssertNil(sources.range(of: #"(?<![A-Za-z])Button\s*(?:\(|\{)"#, options: .regularExpression), "Touched Home surface contains a raw Button")
        for forbidden in ["systemImage:", "Image(systemName:"] {
            XCTAssertFalse(sources.contains(forbidden), "Touched Home surface contains raw presentation: \(forbidden)")
        }
    }

    func testHomeImplementsApprovedTasksOnlyComposerJourney() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let home = try String(contentsOf: root.appendingPathComponent("TaisaApp/Home/HomeView.swift"), encoding: .utf8)
        let sections = try String(contentsOf: root.appendingPathComponent("TaisaApp/Home/ThisWeekSection.swift"), encoding: .utf8)
        let composer = try String(contentsOf: root.appendingPathComponent("TaisaApp/Home/TaskComposerView.swift"), encoding: .utf8)
        let chrome = try String(contentsOf: root.appendingPathComponent("Packages/TaisaFoundation/Sources/TaisaDesignSystem/TaisaPageChrome.swift"), encoding: .utf8)
        let taskRows = try String(contentsOf: root.appendingPathComponent("Packages/TaisaFoundation/Sources/TaisaDesignSystem/TaisaTaskRow.swift"), encoding: .utf8)

        XCTAssertTrue(home.contains("TaisaDatedPageHeader"))
        XCTAssertTrue(home.contains("TaskComposerView"))
        XCTAssertTrue(home.contains("Task added"))
        XCTAssertTrue(home.contains("home.tasks.composer"))
        XCTAssertTrue(home.contains("actions: snapshot.actions"), "Newly created canonical tasks must remain visible after reload")
        XCTAssertTrue(home.contains("ScrollView"), "Figma composition is a free canvas, not a native List")
        XCTAssertFalse(home.contains("List {"), "Native List chrome does not match the Figma frame")
        XCTAssertFalse(home.contains("HomeGoalsSummarySection("))
        XCTAssertFalse(home.contains("LeadInsightSection("))
        XCTAssertFalse(home.contains("HomeReviewSection("))
        XCTAssertTrue(sections.contains("Tasks this week"))
        XCTAssertTrue(taskRows.contains("View all tasks"))
        XCTAssertTrue(chrome.contains("public struct TaisaDatedPageHeader"))
        XCTAssertFalse(chrome.contains("TaskComposerView"), "Feature composition must not live in the design-system layer")
        XCTAssertTrue(composer.contains("TaisaControlMetric.taskComposerHeight"))
        XCTAssertTrue(composer.contains("TaisaButton("))
        XCTAssertNil(composer.range(of: #"(?<![A-Za-z])Button\s*(?:\(|\{)"#, options: .regularExpression))
        XCTAssertTrue(taskRows.contains("TaisaRadius.taskGroup"))
        XCTAssertTrue(taskRows.contains("CentralIcon(.incomplete)"))
        XCTAssertTrue(sections.contains("dueLabel"))
    }

    func testTaskComposerReservesThePrimaryNavigationDockAndStartsClosed() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let home = try String(contentsOf: root.appendingPathComponent("TaisaApp/Home/HomeView.swift"), encoding: .utf8)

        XCTAssertTrue(home.contains("@State private var showsTaskComposer = false"))
        XCTAssertTrue(
            home.contains(".padding(.bottom, TaisaBottomChromeContract.fadeHeight)"),
            "The composer must sit above the shell-owned navigation and voice dock"
        )
    }

    func testInsightsStayNestedByCurrentReviewAndHistoryWithGroundedDetail() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let home = root.appendingPathComponent("TaisaApp/Home")
        let view = try String(contentsOf: home.appendingPathComponent("InsightsView.swift"), encoding: .utf8)
        let detail = try String(contentsOf: home.appendingPathComponent("InsightDetailView.swift"), encoding: .utf8)
        let rootView = try String(contentsOf: root.appendingPathComponent("TaisaApp/App/AppRootView.swift"), encoding: .utf8)

        for identifier in ["insights.root", "insights.current", "insights.review", "insights.history"] {
            XCTAssertTrue(view.contains(identifier), "Missing \(identifier)")
        }
        XCTAssertTrue(view.contains("NavigationLink"))
        XCTAssertFalse(view.contains("Section(\"Sources\")"), "Grounding belongs in nested detail")
        XCTAssertTrue(detail.contains("insight.detail.sources"))
        XCTAssertTrue(detail.contains("insight.detail.revisions"))
        XCTAssertTrue(detail.contains("TaisaChildPageHeader(\"Insight\""))
        XCTAssertTrue(detail.contains(".safeAreaInset(edge: .top, spacing: 0)"))
        XCTAssertTrue(rootView.contains("openInsights:"))
        XCTAssertTrue(rootView.contains("InsightsView(model:"))
    }

    func testPreviewExercisesCombinedHomeAndNestedInsights() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let preview = root.appendingPathComponent("TaisaPreview")
        let scenarios = try String(contentsOf: preview.appendingPathComponent("HomeScenarios.swift"), encoding: .utf8)
        let scenarioView = try String(contentsOf: preview.appendingPathComponent("HomeScenarioView.swift"), encoding: .utf8)

        XCTAssertTrue(scenarios.contains("home.combined"))
        XCTAssertTrue(scenarios.contains("home.insights"))
        XCTAssertTrue(scenarios.contains("thisWeek:"))
        XCTAssertTrue(scenarios.contains("actionPrompts:"))
        XCTAssertTrue(scenarios.contains("reason: .blocked"))
        XCTAssertTrue(scenarios.contains("leadInsight:"))
        XCTAssertTrue(scenarioView.contains("InsightsView(model:"))
        XCTAssertTrue(scenarioView.contains("openInsights:"))
    }

    func testPreviewIncludesDeterministicTaskComposerState() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let preview = root.appendingPathComponent("TaisaPreview")
        let scenarios = try String(contentsOf: preview.appendingPathComponent("HomeScenarios.swift"), encoding: .utf8)
        let scenarioView = try String(contentsOf: preview.appendingPathComponent("HomeScenarioView.swift"), encoding: .utf8)

        XCTAssertTrue(scenarios.contains("home.taskComposer"))
        XCTAssertTrue(scenarios.contains("case taskComposer"))
        XCTAssertTrue(scenarioView.contains("initiallyShowsTaskComposer: mode == .taskComposer"))
        XCTAssertTrue(scenarioView.contains("create:"), "Preview composer must exercise the same create closure as the app")
    }
}
