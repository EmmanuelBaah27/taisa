import Foundation
import XCTest

final class ConversationsViewContractTests: XCTestCase {
    func testChatsPageUsesTheApprovedFigmaHierarchy() throws {
        let source = try conversationsSource()

        for contract in [
            "Text(\"Chats\")", "chats.search", "chats.drafts-filter",
            "List", "listRowBackground", "TaisaRadius.panel"
        ] {
            XCTAssertTrue(source.contains(contract), "Missing Figma Chats contract: \(contract)")
        }
        XCTAssertFalse(source.contains(".navigationTitle(\"Conversations\")"))
    }

    func testChatsVisualRepairUsesDefaultTypographyAndWhiteSeparators() throws {
        let source = try conversationsSource()

        XCTAssertFalse(source.contains("design: .rounded"))
        XCTAssertTrue(source.contains("monthHeader(group.month)"))
        XCTAssertTrue(source.contains("TaisaTypography.metadata.font.weight(.semibold)"))
        XCTAssertTrue(source.contains(".listRowSeparatorTint(TaisaColor.background.color)"))
    }

    func testApplicationIsLockedToLightAppearance() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("TaisaApp/TaisaApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains(".preferredColorScheme(.light)"))
    }

    func testConversationListUsesNativeActionsAndRequiredIdentifiers() throws {
        let source = try conversationsSource()

        for identifier in [
            "conversations.root", "conversations.drafts", "conversations.history",
            "conversations.empty", "conversations.retry", "conversations.recovery",
            "conversation.resume", "conversation.rename", "conversation.delete-confirmation"
        ] {
            XCTAssertTrue(source.contains(identifier), "Missing \(identifier)")
        }
        for nativeControl in ["List", "Section", "swipeActions", "Menu", "confirmationDialog"] {
            XCTAssertTrue(source.contains(nativeControl), "Missing \(nativeControl)")
        }
        XCTAssertFalse(source.contains("New conversation"))
        XCTAssertFalse(source.contains("import GRDB"))
    }

    private func conversationsSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("TaisaApp/Conversations")
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }
}
