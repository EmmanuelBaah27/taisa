import SwiftUI
import TaisaDesignSystem

struct TranscriptCorrectionView: View {
    @Binding var text: String
    let canSubmit: Bool
    let isDirty: Bool
    let isSubmitting: Bool
    let cancel: @MainActor @Sendable () -> Void
    let submit: @MainActor @Sendable () -> Void
    @State private var confirmsDiscard = false

    var body: some View {
        let presentationPolicy = TaisaEditorSheetPolicy(isDirty: isDirty, isBusy: isSubmitting)
        VStack(spacing: 0) {
            editHeader
            ScrollView {
                VStack(alignment: .leading, spacing: TaisaSpacing.control.rawValue) {
                    liquidEditor
                    TaisaText(role: .metadata, color: .mutedForeground, content: "Updating this transcript will regenerate Taisa’s affected reply.")
                        .padding(.horizontal, TaisaSpacing.compact.rawValue)
                    TaisaButton(
                        role: .primary,
                        shape: .capsule,
                        label: "Update and regenerate",
                        isProcessing: isSubmitting,
                        processingAccessibilityLabel: "Saving message",
                        action: submit
                    )
                        .disabled(!canSubmit || isSubmitting)
                        .padding(.top, TaisaSpacing.standard.rawValue)
                }
                .padding(.horizontal, TaisaSpacing.standard.rawValue)
                .padding(.bottom, TaisaSpacing.standard.rawValue)
            }
        }
        .background(TaisaColor.background.color.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .interactiveDismissDisabled(presentationPolicy.blocksInteractiveDismissal)
        .modifier(TaisaNativeConfirmationDialog(
            title: "Discard changes?",
            isPresented: $confirmsDiscard,
            actions: {
                TaisaSystemButton("Discard changes", role: .destructive, action: { cancel() })
                TaisaSystemButton("Keep editing", role: .cancel) {}
            },
            message: { EmptyView() }
        ))
    }

    private var editHeader: some View {
        ZStack {
            TaisaText(role: .navigationLabel, content: "Edit message")
            HStack {
                TaisaSecondaryCapsuleButton(action: requestCancel) {
                    TaisaText(role: .navigationLabel, content: "Cancel")
                        .padding(.horizontal, TaisaSpacing.standard.rawValue)
                }
                .disabled(isSubmitting)
                Spacer()
            }
        }
        .padding(.horizontal, TaisaSpacing.standard.rawValue)
        .frame(height: TaisaControlMetric.appBarHeight)
    }

    @ViewBuilder private var liquidEditor: some View {
        let editor = TextEditor(text: $text)
            .disabled(isSubmitting)
            .scrollContentBackground(.hidden)
            .padding(TaisaSpacing.control.rawValue)
            .frame(minHeight: TaisaControlMetric.messageEditorMinimumHeight)

        editor.modifier(LiquidTextInputSurface(cornerRadius: TaisaRadius.panel.rawValue))
    }

    private func requestCancel() {
        guard !isSubmitting else { return }
        if isDirty { confirmsDiscard = true } else { cancel() }
    }
}
