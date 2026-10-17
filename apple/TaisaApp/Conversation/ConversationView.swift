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
                        updatingResponseAfter: model.correctionRegenerationMessageID,
                        assistantResponses: model.assistantResponses,
                        streamingResponse: model.partialCoaching,
                        correct: model.requestCorrection,
                        saveFeedback: { messageID, direction, factors in
                            Task { await model.saveFeedback(
                                responseMessageID: messageID, direction: direction, factors: factors
                            ) }
                        },
                        acceptProposal: { id in Task { await model.acceptProposal(id) } },
                        dismissProposal: { id in Task { await model.dismissProposal(id) } }
                        )
                        if model.messages.isEmpty { emptyState }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    composer
                        .frame(minHeight: TaisaControlMetric.conversationComposerDockHeight, alignment: .bottom)
                        .zIndex(2)
                }
                ConversationPageHeader(title: model.title, onDismiss: model.requestClose)
                    .accessibilityIdentifier("conversation.close")
                    .zIndex(3)
            }
            .toolbar(.hidden, for: .navigationBar)
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
                    isDirty: model.isCorrectionDirty,
                    isSubmitting: model.isCorrectionSubmitting,
                    cancel: model.cancelCorrection,
                    submit: { Task { await model.submitCorrection() } }
                )
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
            bottomChrome {
                TextComposer(text: $model.text, onSend: { Task { await model.sendText() } }, onVoice: { Task { try? await model.beginVoice() } })
                    .accessibilityIdentifier("conversation.text-composer")
            }
        case .transcribing:
            bottomChrome {
                ConversationProgressState(label: "Transcribing…")
                    .frame(height: TaisaControlMetric.recordingButtonHeight)
                    .frame(maxWidth: .infinity)
            }
        case .coaching:
            VStack(alignment: .leading, spacing: 12) {
                if model.partialCoaching.isEmpty {
                    ConversationProgressState(label: "Preparing coaching…")
                }
                bottomChrome {
                    TextComposer(
                        text: $model.text, mode: .processing,
                        onSend: {}, onVoice: {}
                    )
                    .accessibilityIdentifier("conversation.text-composer.processing")
                }
            }
            .padding(.horizontal)
            .task {
                while !Task.isCancelled, model.composer == .coaching {
                    await model.refreshPartialCoaching()
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        case .waitingForReply:
            bottomChrome { voiceReplyButton }
        case .failure:
            bottomChrome {
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
            Text("What’s on your mind?").font(.system(.body, weight: .medium))
            Text("Talk it through with Taisa.")
                .font(TaisaTypography.body.font)
                .foregroundStyle(TaisaColor.mutedForeground.color)
        }
        .padding()
        .accessibilityElement(children: .combine)
    }

    private var voiceReplyButton: some View {
        HStack {
            Spacer()
            TaisaSecondaryCapsuleButton(action: { Task { try? await model.beginVoice() } }) {
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

    private func bottomChrome<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, TaisaSpacing.standard.rawValue)
            .padding(.top, TaisaSpacing.section.rawValue)
            .padding(.bottom, TaisaSpacing.section.rawValue)
            .frame(minHeight: TaisaControlMetric.conversationComposerDockHeight, alignment: .bottom)
            .background { PageEdgeFade(.navigation).ignoresSafeArea(edges: [.horizontal, .bottom]) }
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
