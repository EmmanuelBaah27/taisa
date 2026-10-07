import XCTest
import TaisaStorage
import TaisaVoice
@testable import Taisa

final class VoiceSessionDiagnosticsViewModelTests: XCTestCase {
    func testActionsDeriveFromDurableState() {
        XCTAssertEqual(model(.draft, .capture).actions, [.record])
        XCTAssertEqual(
            model(.recording, .capture).actions,
            [.pause, .send, .cancel, .discard]
        )
        XCTAssertEqual(
            model(.paused, .capture).actions,
            [.resume, .send, .cancel, .discard]
        )
        XCTAssertEqual(
            model(.awaitingTranscriptConfirmation, .transcription).actions,
            [.confirmTranscript, .cancel, .discard]
        )
        XCTAssertEqual(
            model(.recoverableFailure, .coaching).actions,
            [.retry, .cancel, .discard]
        )
        XCTAssertEqual(
            model(.resumeRequiresConfirmation, .coaching).actions,
            [.confirmResume, .cancel, .discard]
        )
    }

    func testStatusIsTextualAndPrivateContentIsNeverAnnounced() {
        let viewModel = model(.transcribing, .transcription)
        XCTAssertEqual(viewModel.statusTitle, "Transcribing")
        XCTAssertEqual(viewModel.statusAccessibilityLabel, "Voice session status: Transcribing")
        XCTAssertFalse(viewModel.announcesPrivateContent)
    }

    func testReduceMotionDisablesWaveformAnimation() {
        XCTAssertTrue(model(.recording, .capture, reduceMotion: false).animatesWaveform)
        XCTAssertFalse(model(.recording, .capture, reduceMotion: true).animatesWaveform)
        XCTAssertFalse(model(.paused, .capture, reduceMotion: false).animatesWaveform)
    }

    private func model(
        _ state: VoiceTurnState,
        _ stage: VoiceTurnStage,
        reduceMotion: Bool = false
    ) -> VoiceSessionDiagnosticsViewModel {
        VoiceSessionDiagnosticsViewModel(
            snapshot: VoiceSessionSnapshot(
                durable: VoiceTurnRecord(
                    id: UUID().uuidString, conversationID: UUID().uuidString,
                    transcriptionRequestID: UUID().uuidString,
                    transcriptionIdempotencyKey: "t",
                    coachingRequestID: UUID().uuidString,
                    coachingIdempotencyKey: "c",
                    state: state, stage: stage, createdAtMS: 0, updatedAtMS: 0
                ),
                partialTranscript: "private transcript",
                partialCoaching: "private response"
            ),
            reduceMotion: reduceMotion
        )
    }
}
