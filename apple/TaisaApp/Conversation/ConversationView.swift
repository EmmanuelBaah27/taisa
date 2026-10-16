import Foundation
import SwiftUI
import TaisaConversations
import TaisaDesignSystem

struct ConversationView: View {
    @State var model: ConversationViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ConversationPageHeader(title: model.title, onDismiss: model.requestClose)
                    .accessibilityIdentifier("conversation.close")
                ZStack {
                    ConversationTimeline(
                        messages: model.messages,
                        updatingResponseAfter: model.correctionRegenerationMessageID,
                        correct: model.requestCorrection
                    )
                    if model.messages.isEmpty { emptyState }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { composer }
        }
        .accessibilityIdentifier("conversation.root")
        .interactiveDismissDisabled(true)
        .task { await model.start() }
        .sheet(isPresented: Binding(
            get: { model.correctionMessageID != nil },
            set: { if !$0 { model.cancelCorrection() } }
        )) {
            NavigationStack {
                TranscriptCorrectionView(
                    text: $model.correctionText,
                    canSubmit: model.canSubmitCorrection,
                    submit: { Task { await model.submitCorrection() } }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: model.cancelCorrection)
                    }
                }
            }
        }
        .confirmationDialog("Keep this unfinished thought?", isPresented: Binding(
            get: { model.confirmation != nil },
            set: { if !$0 { model.cancelConfirmation() } }
        )) {
            switch model.confirmation {
            case .discardVoiceForKeyboard:
                Button("Switch to keyboard", role: .destructive) { Task { await model.confirmKeyboardReplacement() } }
                Button("Cancel", role: .cancel, action: model.cancelConfirmation)
            case .discardRecording:
                Button("Continue", role: .destructive) { Task { await model.confirmDiscardRecording() } }
                Button("Go back", role: .cancel, action: model.cancelConfirmation)
            case .discardShortOrKeepRecording:
                Button("Discard recording", role: .destructive) { Task { await model.confirmDiscardRecording() } }
                Button("Keep recording", role: .cancel, action: model.cancelConfirmation)
            case .saveDiscardOrCancel:
                Button("Save draft") { Task { await model.saveAndClose() } }.accessibilityIdentifier("conversation.save-draft")
                Button("Discard", role: .destructive) { Task { await model.discardAndClose() } }.accessibilityIdentifier("conversation.discard")
                Button("Cancel", role: .cancel, action: model.cancelConfirmation)
            case nil: EmptyView()
            }
        }
    }

    @ViewBuilder private var composer: some View {
        switch model.composer {
        case .preparingVoice:
            recordingBar(.preparing)
        case .recording:
            recordingBar(actionPhase)
                .task {
                    while !Task.isCancelled, model.composer == .recording {
                        await model.refreshCapture()
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }
        case .paused:
            recordingBar(pausedActionPhase)
        case .savedVoiceDraft:
            recordingBar(.saved)
        case .typing:
            TextComposer(text: $model.text, onSend: { Task { await model.sendText() } }, onVoice: { Task { try? await model.beginVoice() } })
                .accessibilityIdentifier("conversation.text-composer")
        case .transcribing:
            ConversationProgressState(label: "Transcribing…")
        case .coaching:
            VStack(alignment: .leading, spacing: 12) {
                if let transcript = model.latestUserTranscript {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("You")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(transcript)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("conversation.transcript-preview")
                }
                if model.partialCoaching.isEmpty {
                    ConversationProgressState(label: "Preparing coaching…")
                } else if let markdown = try? AttributedString(markdown: model.partialCoaching) {
                    Text(markdown)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("conversation.streaming-response")
                }
                TextComposer(
                    text: $model.text, mode: .processing,
                    onSend: {}, onVoice: {}
                )
                .accessibilityIdentifier("conversation.text-composer.processing")
            }
            .padding(.horizontal)
            .task {
                while !Task.isCancelled, model.composer == .coaching {
                    await model.refreshPartialCoaching()
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        case .waitingForReply:
            TextComposer(text: $model.text, onSend: { Task { await model.sendText() } }, onVoice: { Task { try? await model.beginVoice() } })
                .accessibilityIdentifier("conversation.text-composer")
        case .failure:
            InlineRecoveryAlert(
                contract: recoveryContract,
                onCancel: model.cancelRecoveryAndClose,
                onRetry: { Task { await model.retry() } }
            )
            .accessibilityIdentifier("conversation.retry")
        }
    }

    private var recoveryContract: InlineRecoveryAlert.Contract {
        switch model.failureContext {
        case .request: .request
        case .beginRecording: .beginRecording
        case .pauseRecording: .pauseRecording
        case .resumeRecording: .resumeRecording
        }
    }

    private var actionPhase: ConversationActionBar.Phase {
        switch model.capture.disposition {
        case .empty: .recording
        case .shortCapture: .shortCapture
        case .sendable: .sendable
        case .durableProcessing: .waitingForReply
        }
    }

    private var pausedActionPhase: ConversationActionBar.Phase {
        switch model.capture.disposition {
        case .empty: .pausedEmpty
        case .shortCapture: .pausedShort
        case .sendable: .paused
        case .durableProcessing: .waitingForReply
        }
    }

    private func recordingBar(_ phase: ConversationActionBar.Phase) -> some View {
        ConversationActionBar(
            phase: phase, elapsed: elapsed,
            onDiscard: model.requestDiscardRecording,
            onKeyboard: model.requestKeyboard,
            onPrimary: {
                Task {
                    switch phase {
                    case .pausedEmpty, .pausedShort, .paused: await model.resume()
                    case .recording, .shortCapture, .sendable: await model.pause()
                    case .preparing, .saved, .waitingForReply: break
                    }
                }
            },
            onSend: { Task { await model.sendVoice() } }
        )
        .accessibilityIdentifier("conversation.voice-composer")
    }

    private var elapsed: String {
        let seconds = model.capture.elapsedMilliseconds / 1_000
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            CentralIcon(.voiceMid).frame(width: 40, height: 40)
            Text("What’s on your mind?").font(.title2.weight(.semibold))
            Text("Talk it through with Taisa.").foregroundStyle(.secondary)
        }
        .padding()
        .accessibilityElement(children: .combine)
    }
}
