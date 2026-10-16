import SwiftUI
import TaisaDesignSystem

struct TranscriptCorrectionView: View {
    @Binding var text: String
    let canSubmit: Bool
    let cancel: @MainActor @Sendable () -> Void
    let submit: @MainActor @Sendable () -> Void

    var body: some View {
        VStack(spacing: 0) {
            editHeader
            ScrollView {
                VStack(alignment: .leading, spacing: TaisaSpacing.control.rawValue) {
                    liquidEditor
                    Text("Updating this transcript will regenerate Taisa’s affected reply.")
                        .font(TaisaTypography.metadata.font)
                        .foregroundStyle(TaisaColor.mutedForeground.color)
                        .padding(.horizontal, TaisaSpacing.compact.rawValue)
                    TaisaButton(role: .primary, label: "Update and regenerate", action: submit)
                        .disabled(!canSubmit)
                        .padding(.top, TaisaSpacing.standard.rawValue)
                }
                .padding(.horizontal, TaisaSpacing.standard.rawValue)
                .padding(.bottom, TaisaSpacing.standard.rawValue)
            }
        }
        .background(TaisaColor.background.color.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var editHeader: some View {
        ZStack {
            Text("Edit message").font(TaisaTypography.navigationLabel.font)
            HStack {
                TaisaSecondaryCapsuleButton(action: cancel) {
                    Text("Cancel")
                        .font(TaisaTypography.navigationLabel.font)
                        .padding(.horizontal, TaisaSpacing.standard.rawValue)
                }
                Spacer()
            }
        }
        .padding(.horizontal, TaisaSpacing.standard.rawValue)
        .frame(height: TaisaControlMetric.appBarHeight)
    }

    @ViewBuilder private var liquidEditor: some View {
        let editor = TextEditor(text: $text)
            .scrollContentBackground(.hidden)
            .padding(TaisaSpacing.control.rawValue)
            .frame(minHeight: 120)

        if #available(iOS 26.0, *) {
            editor.glassEffect(.regular, in: RoundedRectangle(cornerRadius: TaisaRadius.panel.rawValue))
        } else {
            editor
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: TaisaRadius.panel.rawValue))
                .overlay {
                    RoundedRectangle(cornerRadius: TaisaRadius.panel.rawValue)
                        .stroke(TaisaColor.border.color)
                }
        }
    }
}
