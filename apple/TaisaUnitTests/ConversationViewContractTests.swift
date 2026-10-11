import Foundation
import XCTest

final class ConversationViewContractTests: XCTestCase {
    func testConversationOpenFailureReportsAContentFreeStage() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("TaisaApp/Conversation/ConversationRuntimeFactory.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("enum ConversationOpenStage: String"))
        XCTAssertTrue(source.contains("conversation.unavailable.diagnostic"))
        XCTAssertTrue(source.contains("openStage(.resumableTurn)"))
        XCTAssertTrue(source.contains("TAISA_CONVERSATION_OPEN_FAILURE stage="))
        XCTAssertFalse(source.contains("error.localizedDescription"))
    }

    func testLatestDraftDiagnosticReportsOnlyContentFreeFields() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let factory = try String(
            contentsOf: root.appendingPathComponent("TaisaApp/Conversation/ConversationRuntimeFactory.swift"),
            encoding: .utf8
        )
        let appRoot = try String(
            contentsOf: root.appendingPathComponent("TaisaApp/App/AppRootView.swift"),
            encoding: .utf8
        )
        let diagnosticStart = try XCTUnwrap(factory.range(of: "func contentFreeLatestDraftDiagnostic"))
        let remainder = factory[diagnosticStart.lowerBound...]
        let diagnosticEnd = try XCTUnwrap(remainder.range(of: "\n    func makeModel"))
        let diagnostic = String(remainder[..<diagnosticEnd.lowerBound])

        XCTAssertTrue(factory.contains("contentFreeLatestDraftDiagnostic"))
        XCTAssertTrue(diagnostic.contains("state=\\(turn.state.rawValue) stage=\\(turn.stage.rawValue) failure=\\(turn.failureCode ?? \"none\")"))
        XCTAssertFalse(diagnostic.contains("acceptedTranscript"))
        XCTAssertFalse(diagnostic.contains("requestID"))
        XCTAssertTrue(appRoot.contains("--taisa-diagnose-latest-preserved-draft"))
        XCTAssertTrue(appRoot.contains("TAISA_CONVERSATION_DRAFT_DIAGNOSTIC"))
    }

    func testLegacyVoiceDraftDecodeFailureFallsThroughToTranscriptRecovery() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("TaisaApp/Conversation/ConversationRuntimeFactory.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("let voiceTurn = try? await turns.turn(id: voiceTurnID)"))
        XCTAssertTrue(source.contains("linkedVoiceTurn = try? await turns.turn(id: voiceTurnID)"))
        XCTAssertTrue(source.contains("recoveryTranscript: recoveryTranscript ?? lastUserMessage?.body"))
    }

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
            "conversation.correct-transcript", "conversation.transcript-preview"
        ] {
            XCTAssertTrue(source.contains(identifier), "Missing \(identifier)")
        }
        XCTAssertTrue(source.contains("interactiveDismissDisabled"))
        XCTAssertTrue(source.contains("confirmationDialog"))
        XCTAssertTrue(source.contains("ScrollViewReader"))
        XCTAssertTrue(source.contains("onChange(of: messages.last?.id"))
        XCTAssertTrue(source.contains("latestUserTranscript"))
        XCTAssertFalse(source.contains("import GRDB"))
    }
}
