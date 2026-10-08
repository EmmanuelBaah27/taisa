import Foundation
import XCTest

final class ConversationViewContractTests: XCTestCase {
    func testConversationScreenExposesRequiredNativeInteractionContracts() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("TaisaApp/Conversation")
        let source = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        for identifier in [
            "conversation.root", "conversation.close", "conversation.timeline",
            "conversation.voice-composer", "conversation.text-composer",
            "conversation.save-draft", "conversation.discard", "conversation.retry",
            "conversation.correct-transcript"
        ] {
            XCTAssertTrue(source.contains(identifier), "Missing \(identifier)")
        }
        XCTAssertTrue(source.contains("interactiveDismissDisabled"))
        XCTAssertTrue(source.contains("confirmationDialog"))
        XCTAssertFalse(source.contains("import GRDB"))
    }
}
