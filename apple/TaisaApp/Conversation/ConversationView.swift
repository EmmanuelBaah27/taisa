import SwiftUI
import TaisaConversations
import TaisaDesignSystem

struct ConversationView: View {
    @State var model: ConversationViewModel

    var body: some View {
        NavigationStack {
            ConversationTimeline(messages: model.messages, correct: model.requestCorrection)
                .navigationTitle(model.title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: model.requestClose)
                            .accessibilityIdentifier("conversation.close")
                    }
                }
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
            ConversationProgressState(label: "Preparing microphone…")
        case .recording:
            VoiceComposerControls(
                phase: .recording,
                onPrimary: { Task { await model.pause() } },
                onSend: { Task { await model.sendVoice() } },
                onKeyboard: model.requestKeyboard
            )
                .accessibilityIdentifier("conversation.voice-composer")
        case .paused:
            VoiceComposerControls(
                phase: .paused,
                onPrimary: { Task { await model.resume() } },
                onSend: { Task { await model.sendVoice() } },
                onKeyboard: model.requestKeyboard
            )
                .accessibilityIdentifier("conversation.voice-composer")
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
                ConversationProgressState(label: "Preparing coaching…")
            }
            .padding(.horizontal)
        case .waitingForReply:
            VoiceComposerControls(phase: .waitingForReply, onPrimary: { Task { try? await model.beginVoice() } }, onSend: {})
                .accessibilityIdentifier("conversation.voice-composer")
        case .failure:
            ConversationFailureActions(
                message: "Unable to continue.",
                onRetry: { Task { await model.retry() } },
                onSave: { Task { await model.saveAndClose() } },
                onDiscard: { Task { await model.discardAndClose() } }
            )
            .accessibilityIdentifier("conversation.retry")
        }
    }
}
