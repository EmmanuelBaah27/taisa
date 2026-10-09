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
}
