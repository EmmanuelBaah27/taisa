import SwiftUI

public enum TaisaGraphicalDatePickerContract {
    public static let tint = TaisaColor.primaryAction
}

public struct TaisaDateSelectionDraft: Sendable, Equatable {
    private let initial: Date
    public var selection: Date

    public init(initial: Date) {
        self.initial = initial
        selection = initial
    }

    public var cancelledValue: Date { initial }
    public var committedValue: Date { selection }
}

public struct TaisaGraphicalDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TaisaDateSelectionDraft
    private let title: String
    private let cancel: @MainActor () -> Void
    private let commit: @MainActor (Date) -> Void

    public init(
        title: String = "Due date",
        selection: Date,
        cancel: @escaping @MainActor () -> Void = {},
        commit: @escaping @MainActor (Date) -> Void
    ) {
        self.title = title
        _draft = State(initialValue: TaisaDateSelectionDraft(initial: selection))
        self.cancel = cancel
        self.commit = commit
    }

    public var body: some View {
        VStack(spacing: TaisaSpacing.compact.rawValue) {
            ZStack {
                TaisaText(role: .heading, content: title)
                HStack {
                    TaisaButton(role: .ghost, label: "Cancel", size: .small, layout: .intrinsic) {
                        cancel()
                        dismiss()
                    }
                    Spacer()
                    TaisaButton(role: .primary, label: "Done", size: .small, layout: .intrinsic) {
                        commit(draft.committedValue)
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, TaisaSpacing.standard.rawValue)

            DatePicker(title, selection: $draft.selection, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(TaisaGraphicalDatePickerContract.tint.color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, TaisaSpacing.control.rawValue)
        }
        .padding(.top, TaisaSpacing.compact.rawValue)
        .background(TaisaColor.background.color)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
