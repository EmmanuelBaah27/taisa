import Foundation
import SwiftUI
import TaisaConversations
import TaisaDesignSystem
import UIKit

struct ConversationView: View {
    @State var model: ConversationViewModel

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                StatusBarBackground()
                    .zIndex(4)
                VStack(spacing: 0) {
                    ZStack {
                        ConversationTimeline(
                            messages: model.messages,
                            conversationID: model.conversationID,
                            assistantResponses: model.assistantResponses,
                            updatingResponseAfter: model.correctionRegenerationMessageID,
                            failedResponseUpdateAfter: model.correctionRegenerationFailureMessageID,
                            streamingResponse: model.partialCoaching,
                            streamingFinalMessageID: model.streamingFinalMessageID,
                            isSendingText: model.isSendingText,
                            isThinking: model.composer == .coaching && model.partialCoaching.isEmpty,
                            isStreamingResponse: model.isResponseStreaming,
                            isInitialLoadComplete: model.isInitialLoadComplete,
                            streamingDidFinish: model.completeStreamingPresentation,
                            retryResponseUpdate: { Task { await model.retryCorrectionRegeneration() } },
                            keepEditedMessage: model.keepEditedMessage,
                            correct: model.requestCorrection,
                            saveFeedback: { messageID, direction, factors, detail in
                                Task { await model.saveFeedback(
                                    responseMessageID: messageID, direction: direction,
                                    factors: factors, detail: detail
                                ) }
                            },
                            acceptProposal: { id in Task { await model.acceptProposal(id) } },
                            dismissProposal: { id in Task { await model.dismissProposal(id) } }
                        )
                        if model.messages.isEmpty { emptyState }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let responseActionFailure = model.responseActionFailure {
                    TaisaToast(
                        message: responseActionFailure.message,
                        actionLabel: "Try again",
                        action: { Task { await model.retryFailedResponseAction() } },
                        dismiss: model.clearResponseActionFailure
                    )
                    .padding(.top, TaisaControlMetric.appBarHeight + TaisaSpacing.compact.rawValue)
                    .zIndex(5)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                ConversationPageHeader(title: model.title, onDismiss: model.requestClose)
                    .accessibilityIdentifier("conversation.close")
                    .disabled(model.closeActionDisabled)
                    .zIndex(3)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composer
                    .zIndex(2)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .opacity(model.isClosing ? 0 : 1)
        .background(TaisaColor.background.color.ignoresSafeArea())
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
                    isDirty: model.isCorrectionDirty,
                    isSubmitting: model.isCorrectionSubmitting,
                    cancel: model.cancelCorrection,
                    submit: { Task { await model.submitCorrection() } }
                )
            }
        }
        .confirmationDialog("Keep this unfinished thought?", isPresented: Binding(
            get: { model.confirmation != nil },
            // Each dialog action owns clearing the pending confirmation. SwiftUI
            // writes `false` while dismissing a tapped action, before an async
            // action's task necessarily starts; clearing here can erase the
            // command that action is about to confirm.
            set: { _ in }
        )) {
            Group {
                switch model.confirmation {
                case .discardVoiceForKeyboard:
                    Button("Switch to keyboard", role: .destructive, action: model.confirmKeyboardReplacement)
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
            .disabled(model.actionInFlight)
        }
    }

    @ViewBuilder private var composer: some View {
        ConversationComposerChrome {
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
                VStack(spacing: TaisaSpacing.control.rawValue) {
                    if model.showsMicrophoneUnavailable {
                        TaisaToast(
                            message: "Microphone unavailable. Resume when the call ends.",
                            dismiss: model.dismissMicrophoneUnavailable
                        )
                    }
                    recordingBar(pausedActionPhase)
                }
                .task {
                    while !Task.isCancelled, model.composer == .paused {
                        await model.refreshCapture()
                        try? await Task.sleep(for: .milliseconds(250))
                    }
                }
            case .savedVoiceDraft:
                recordingBar(.saved)
            case .typing:
                TextComposer(
                    text: $model.text,
                    onSend: { Task { await model.sendText() } },
                    onVoice: { Task { try? await model.beginVoice() } }
                )
                .transition(.identity)
                .accessibilityIdentifier("conversation.text-composer")
            case .transcribing:
                ConversationProgressState(label: "Transcribing…")
                    .frame(height: TaisaControlMetric.recordingButtonHeight)
                    .frame(maxWidth: .infinity)
            case .coaching:
                voiceReplyButton.disabled(true)
                .task {
                    while !Task.isCancelled, model.composer == .coaching {
                        await model.refreshPartialCoaching()
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }
            case .waitingForReply:
                voiceReplyButton
            case .failure:
                InlineRecoveryAlert(
                    contract: recoveryContract,
                    onCancel: performRecoverySecondaryAction,
                    onRetry: performRecoveryPrimaryAction
                )
                .accessibilityIdentifier("conversation.retry")
            }
        }
    }

    private var recoveryContract: InlineRecoveryAlert.Contract {
        switch model.failureContext {
        case .transcription: .transcription
        case .request: .request
        case .beginRecording: .beginRecording
        case .microphonePermissionDenied: .microphonePermission
        case .pauseRecording: .pauseRecording
        case .resumeRecording: .resumeRecording
        }
    }

    private var actionPhase: ConversationActionBar.Phase {
        switch model.capture.disposition {
        case .empty: .recording
        case .shortCapture: .shortCapture
        case .sendable: .sendable
        case .durableProcessing: .recording
        }
    }

    private var pausedActionPhase: ConversationActionBar.Phase {
        switch model.capture.disposition {
        case .empty: .pausedEmpty
        case .shortCapture: .pausedShort
        case .sendable: .paused
        case .durableProcessing: .paused
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
        .disabled(model.actionInFlight && model.composer != .preparingVoice)
        .opacity(
            model.actionInFlight && model.composer != .preparingVoice
                ? TaisaControlMetric.disabledControlOpacity
                : 1
        )
        .accessibilityIdentifier("conversation.voice-composer")
    }

    private var elapsed: String {
        let seconds = model.capture.elapsedMilliseconds / 1_000
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var emptyState: some View {
        VStack(spacing: TaisaSpacing.control.rawValue) {
            CentralIcon(.voiceMid)
                .frame(
                    width: TaisaControlMetric.conversationEmptyVoiceIcon,
                    height: TaisaControlMetric.conversationEmptyVoiceIcon
                )
                .foregroundStyle(TaisaColor.mutedForeground.color)
            Text("What’s on your mind?").font(TaisaTypography.navigationLabel.font)
            Text("Talk it through with Taisa.")
                .font(TaisaTypography.supporting.font)
                .foregroundStyle(TaisaColor.mutedForeground.color)
        }
        .padding(TaisaSpacing.standard.rawValue)
        .accessibilityElement(children: .combine)
    }

    private var voiceReplyButton: some View {
        HStack {
            Spacer()
            TaisaSecondaryCapsuleButton(
                height: TaisaControlMetric.recordingButtonHeight,
                action: { Task { try? await model.beginVoice() } }
            ) {
                HStack(spacing: TaisaSpacing.compact.rawValue) {
                    CentralIcon(.voiceMid)
                        .frame(width: TaisaControlMetric.standardIcon, height: TaisaControlMetric.standardIcon)
                    Text("Reply").font(TaisaTypography.navigationLabel.font)
                }
                .foregroundStyle(TaisaColor.foreground.color)
                .padding(.horizontal, TaisaSpacing.page.rawValue)
                .frame(height: TaisaControlMetric.recordingButtonHeight)
            }
            .accessibilityLabel("Reply by voice, starts recording")
            .accessibilityIdentifier("conversation.voice-reply")
            Spacer()
        }
    }

    private func performRecoveryPrimaryAction() {
        if model.failureContext == .microphonePermissionDenied,
           let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL, options: [:])
        } else {
            Task { await model.retry() }
        }
    }

    private func performRecoverySecondaryAction() {
        switch model.failureContext {
        case .transcription:
            Task { await model.saveAndClose() }
        case .microphonePermissionDenied:
            model.continueWithKeyboardAfterPermissionDenial()
        case .beginRecording:
            model.continueWithKeyboardAfterRecordingFailure()
        case .pauseRecording:
            Task { await model.confirmDiscardRecording() }
        case .resumeRecording:
            Task { await model.saveAndClose() }
        case .request:
            model.cancelRecoveryAndClose()
        }
    }
}

private struct StatusBarBackground: View {
    var body: some View {
        TaisaColor.background.color
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(edges: .top)
    }
}
