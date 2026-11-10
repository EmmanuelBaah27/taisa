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

        for identifier in ["home.root", "home.conversations", "home.goals.summary", "home.actions.preview", "home.empty", "home.retry", "home.recovery"] {
            XCTAssertTrue(sources.contains(identifier), "Missing \(identifier)")
        }
        XCTAssertFalse(sources.contains("import GRDB"))
        XCTAssertTrue(sources.contains("NavigationStack"))
        XCTAssertTrue(sources.contains("ContentUnavailableView"))
        XCTAssertTrue(sources.contains("refreshable"))
    }

    func testCombinedHomeUsesTheApprovedCalmSectionOrder() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let home = root.appendingPathComponent("TaisaApp/Home")
        let homeView = try String(contentsOf: home.appendingPathComponent("HomeView.swift"), encoding: .utf8)
        let thisWeek = try String(contentsOf: home.appendingPathComponent("ThisWeekSection.swift"), encoding: .utf8)
        let leadInsight = try String(contentsOf: home.appendingPathComponent("LeadInsightSection.swift"), encoding: .utf8)

        XCTAssertTrue(homeView.contains("if let leadInsight = snapshot.leadInsight"))
        XCTAssertTrue(homeView.contains("LeadInsightSection(insight: leadInsight"))
        XCTAssertTrue(homeView.contains("ThisWeekSection("))
        let focus = try XCTUnwrap(homeView.range(of: "ThisWeekSection(")?.lowerBound)
        let actions = try XCTUnwrap(homeView.range(of: "HomeActionsPreviewSection(")?.lowerBound)
        let goals = try XCTUnwrap(homeView.range(of: "HomeGoalsSummarySection(")?.lowerBound)
        let insight = try XCTUnwrap(homeView.range(of: "LeadInsightSection(insight: leadInsight")?.lowerBound)
        let review = try XCTUnwrap(homeView.range(of: "HomeReviewSection(")?.lowerBound)
        XCTAssertLessThan(focus, actions)
        XCTAssertLessThan(actions, goals)
        XCTAssertLessThan(goals, insight)
        XCTAssertLessThan(insight, review)
        XCTAssertTrue(homeView.contains("snapshot.hasConfirmedInsightHistory"))
        XCTAssertTrue(homeView.contains("home.insights.link"))

        for identifier in ["home.this-week", "home.prior-week.review", "home.actions.preview", "home.actions.view-all", "home.goals.summary", "home.goals.view-all"] {
            XCTAssertTrue(thisWeek.contains(identifier), "Missing \(identifier)")
        }
        XCTAssertFalse(thisWeek.contains("await model.undoCompletion()"))
        XCTAssertFalse(thisWeek.contains("home.this-week.complete"))
        XCTAssertTrue(thisWeek.contains("TaisaRow("))
        XCTAssertFalse(thisWeek.contains("systemImage:"), "Touched Home Action UI must use Central Icons")
        XCTAssertTrue(leadInsight.contains("home.lead-insight"))
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
}
