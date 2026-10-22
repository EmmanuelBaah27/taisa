import Foundation
import XCTest

final class CareerWorkViewContractTests: XCTestCase {
    func testJourneyUsesAdaptiveNativeNavigationAndExplicitStates() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("TaisaApp/CareerWork/CareerWorkView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("NavigationSplitView"))
        XCTAssertTrue(source.contains("NavigationStack"))
        XCTAssertTrue(source.contains("TaisaChildPageHeader(detailTitle"))
        XCTAssertTrue(source.contains("horizontalSizeClass == .regular ? .detail : .back"))
        XCTAssertTrue(source.contains(".safeAreaInset(edge: .top, spacing: 0)"))
        XCTAssertTrue(source.contains("career-work.empty"))
        XCTAssertTrue(source.contains("career-work.retry"))
        XCTAssertTrue(source.contains("career-work.recovery"))
        XCTAssertTrue(source.contains("accessibilityLabel"))
        XCTAssertTrue(source.contains("career-work.proposal.review"))
        XCTAssertTrue(source.contains("Origin:"))
        XCTAssertTrue(source.contains("Add milestone"))
        XCTAssertTrue(source.contains("Add action"))
        XCTAssertTrue(source.contains("Add evidence"))
        XCTAssertFalse(source.contains("Color("))
    }
}
