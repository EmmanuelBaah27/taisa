import Foundation
import XCTest

final class HomeViewContractTests: XCTestCase {
    func testHomeUsesRequiredNativeStateIdentifiersAndNoGRDB() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let home = root.appendingPathComponent("TaisaApp/Home")
        let sources = try FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        for identifier in ["home.root", "home.conversations", "home.goals", "home.actions", "home.empty", "home.retry", "home.recovery"] {
            XCTAssertTrue(sources.contains(identifier), "Missing \(identifier)")
        }
        XCTAssertFalse(sources.contains("import GRDB"))
        XCTAssertTrue(sources.contains("NavigationStack"))
        XCTAssertTrue(sources.contains("ContentUnavailableView"))
        XCTAssertTrue(sources.contains("refreshable"))
    }

    func testCombinedHomeKeepsTheLeadInsightConditionalAndWeeklyWorkPrimary() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let home = root.appendingPathComponent("TaisaApp/Home")
        let homeView = try String(contentsOf: home.appendingPathComponent("HomeView.swift"), encoding: .utf8)
        let thisWeek = try String(contentsOf: home.appendingPathComponent("ThisWeekSection.swift"), encoding: .utf8)
        let leadInsight = try String(contentsOf: home.appendingPathComponent("LeadInsightSection.swift"), encoding: .utf8)

        XCTAssertTrue(homeView.contains("if let leadInsight = snapshot.leadInsight"))
        XCTAssertTrue(homeView.contains("LeadInsightSection(insight: leadInsight"))
        XCTAssertTrue(homeView.contains("ThisWeekSection("))
        XCTAssertLessThan(
            try XCTUnwrap(homeView.range(of: "LeadInsightSection(insight: leadInsight")?.lowerBound),
            try XCTUnwrap(homeView.range(of: "ThisWeekSection(")?.lowerBound)
        )
        XCTAssertTrue(homeView.contains("snapshot.hasConfirmedInsightHistory"))
        XCTAssertTrue(homeView.contains("home.insights.link"))

        for identifier in ["home.this-week", "home.this-week.complete", "home.this-week.undo", "home.prior-week.review"] {
            XCTAssertTrue(thisWeek.contains(identifier), "Missing \(identifier)")
        }
        XCTAssertTrue(thisWeek.contains("await model.complete(actionID:"))
        XCTAssertTrue(thisWeek.contains("await model.undoCompletion()"))
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
        XCTAssertTrue(rootView.contains("openInsights:"))
        XCTAssertTrue(rootView.contains("InsightsView(model:"))
    }
}
