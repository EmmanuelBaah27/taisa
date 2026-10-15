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
        XCTAssertTrue(source.contains(".system(size: 14, weight: .medium)"))
        XCTAssertTrue(source.contains(".listRowSeparatorTint(TaisaColor.background.color)"))
        XCTAssertTrue(source.contains(".lineLimit(2)"))
        XCTAssertTrue(source.contains("preview: snapshot.lastMessagePreview"))
        XCTAssertTrue(source.contains(".frame(height: 48)"))
    }

    func testChatsRowsUseTwelvePointVerticalPaddingAndFullWidthDividers() throws {
        let source = try conversationsSource()

        XCTAssertTrue(source.contains(".padding(.vertical, TaisaSpacing.control.rawValue)"))
        XCTAssertTrue(source.contains(".alignmentGuide(.listRowSeparatorLeading) { _ in 0 }"))
        XCTAssertTrue(source.contains(".alignmentGuide(.listRowSeparatorTrailing) { dimensions in dimensions.width }"))
    }

    func testChatsControlsUseCentralIconsLiquidGlassAndHeaderFade() throws {
        let source = try conversationsSource()

        XCTAssertTrue(source.contains("CentralIcon(.magnifyingGlass)"))
        XCTAssertTrue(source.contains(".buttonStyle(.glass)"))
        XCTAssertTrue(source.contains("PageEdgeFade(.header)"))
        XCTAssertFalse(source.contains("Image(systemName: \"magnifyingglass\")"))
    }

    func testDraftFilterIsConditionalAndMonthHeaderHasNoHorizontalInset() throws {
        let source = try conversationsSource()

        XCTAssertTrue(source.contains("if hasDrafts"))
        XCTAssertTrue(source.contains("if !showsDraftsOnly || snapshot.drafts.isEmpty"))
        XCTAssertTrue(source.contains(".listSectionMargins(.horizontal, 0)"))
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
