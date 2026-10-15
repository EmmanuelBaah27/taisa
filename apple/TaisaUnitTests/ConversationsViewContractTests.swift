import Foundation
import XCTest

final class ConversationsViewContractTests: XCTestCase {
    func testChatsPageUsesTheApprovedFigmaHierarchy() throws {
        let source = try conversationsSource()

        for contract in [
            "Text(\"Chats\")", "chats.search", "chats.drafts-filter",
            "List", "listRowBackground", "TaisaRadius.historyGroup"
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
        XCTAssertFalse(source.contains(".lineLimit(2)"))
        XCTAssertTrue(source.contains("preview: snapshot.lastMessagePreview"))
        XCTAssertTrue(source.contains(".frame(height: 48)"))
    }

    func testChatsRowsMatchTheMeasuredFigmaRecord() throws {
        let source = try conversationsSource()

        XCTAssertTrue(source.contains(".padding(.vertical, TaisaSpacing.control.rawValue)"))
        XCTAssertTrue(source.contains(".frame(height: 2)"))
        XCTAssertTrue(source.contains(".listRowInsets(EdgeInsets())"))
        XCTAssertTrue(source.contains(".listStyle(.plain)"))
        XCTAssertTrue(source.contains("TaisaColor.subtleSurface.color"))
        XCTAssertTrue(source.contains(".padding(.horizontal, TaisaSpacing.standard.rawValue)"))
        XCTAssertTrue(source.contains("TaisaRadius.historyGroup.rawValue"))
    }

    func testHistoryRowsDoNotPaintOverTheRoundedGroupBackground() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("TaisaApp/Conversations/ConversationHistoryRow.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains(".background(TaisaColor.subtleSurface.color)"))
        XCTAssertTrue(source.contains(".lineLimit(1)"))
        XCTAssertTrue(source.contains(".truncationMode(.tail)"))
    }

    func testChatsControlsUseCentralIconsLiquidGlassAndHeaderFade() throws {
        let source = try conversationsSource()

        XCTAssertTrue(source.contains("CentralIcon(.magnifyingGlass)"))
        XCTAssertTrue(source.contains(".frame(width: 24, height: 24)"))
        XCTAssertTrue(source.contains(".buttonStyle(.glass)"))
        XCTAssertTrue(source.contains("PageEdgeFade(.header)"))
        XCTAssertTrue(source.contains(".frame(height: 64)"))
        XCTAssertTrue(source.contains(".offset(y: TaisaSpacing.section.rawValue)"))
        XCTAssertFalse(source.contains("Image(systemName: \"magnifyingglass\")"))
    }

    func testDraftFilterIsConditionalAndMonthHeaderHasNoHorizontalInset() throws {
        let source = try conversationsSource()

        XCTAssertTrue(source.contains("if hasDrafts"))
        XCTAssertTrue(source.contains("if !showsDraftsOnly || snapshot.drafts.isEmpty"))
        XCTAssertTrue(source.contains(".listSectionMargins(.horizontal, 0)"))
        XCTAssertTrue(source.contains(".scrollIndicators(.hidden)"))
        XCTAssertFalse(source.contains("} header: {"))
    }

    func testApplicationIsLockedToLightAppearance() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("TaisaApp/TaisaApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains(".preferredColorScheme(.light)"))
    }

    func testChatsVisualQAExercisesTheRealAppShell() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("TaisaApp/App/AppRootView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("--taisa-chats-visual-qa"))
        XCTAssertTrue(source.contains("PrimaryAppShellModel(selection: .conversations)"))
        XCTAssertTrue(source.contains("chatsVisualQASnapshot"))
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
        for nativeControl in ["List", "Section", "contextMenu", "confirmationDialog"] {
            XCTAssertTrue(source.contains(nativeControl), "Missing \(nativeControl)")
        }
        XCTAssertFalse(source.contains("swipeActions"))
        XCTAssertFalse(source.contains("Menu(\"Actions\")"))
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
