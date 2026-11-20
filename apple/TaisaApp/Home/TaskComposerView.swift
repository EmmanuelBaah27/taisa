import SwiftUI
import TaisaDesignSystem
#if canImport(UIKit)
import UIKit
#endif

struct TaskComposerView: View {
    @FocusState private var titleIsFocused: Bool
    @State private var keyboardHeight: CGFloat = 0
    @State private var showsDueDatePicker = false
    @State private var draftDueDate = Date()
    @Binding private var title: String
    @Binding private var dueDate: Date?
    private let submit: @MainActor () -> Void

    init(title: Binding<String>, dueDate: Binding<Date?>, submit: @escaping @MainActor () -> Void) {
        _title = title
        _dueDate = dueDate
        self.submit = submit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TaisaSpacing.control.rawValue) {
            TaisaTaskTitleField(text: $title, focus: $titleIsFocused)
            HStack {
                TaisaButton(
                    role: .ghost,
                    shape: .capsule,
                    label: dueDate?.taskComposerLabel ?? "Due",
                    icon: .calendar,
                    size: .small,
                    layout: .intrinsic,
                    accessibilityLabel: dueDate.map { "Due date, \($0.taskComposerLabel)" } ?? "Due"
                ) {
                    draftDueDate = dueDate ?? Date()
                    titleIsFocused = false
                    showsDueDatePicker = true
                }
                .accessibilityIdentifier("task.composer.due")

                Spacer(minLength: 0)

                TaisaButton(
                    role: .primary,
                    shape: .circle,
                    label: "",
                    icon: .arrowUp,
                    size: .small,
                    layout: .intrinsic,
                    isEnabled: !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    accessibilityLabel: "Save task",
                    action: submit
                )
                .accessibilityIdentifier("task.composer.submit")
            }
        }
        .padding(TaisaSpacing.control.rawValue)
        .frame(height: TaisaControlMetric.taskComposerCardHeight)
        .background(TaisaColor.background.color)
        .clipShape(RoundedRectangle(cornerRadius: TaisaRadius.taskComposer))
        .overlay { RoundedRectangle(cornerRadius: TaisaRadius.taskComposer).stroke(TaisaColor.border.color.opacity(0.7)) }
        .shadow(
            color: TaisaColor.foreground.color.opacity(TaisaEffect.taskComposerShadowOpacity),
            radius: TaisaEffect.taskComposerShadowRadius
        )
        .padding(TaisaSpacing.control.rawValue)
        .frame(height: TaisaControlMetric.taskComposerHeight)
        .background { PageEdgeFade(.navigation) }
        .padding(.bottom, keyboardHeight)
        .task { titleIsFocused = true }
#if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            keyboardHeight = keyboardEndFrame(from: notification).height
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
#endif
        .sheet(isPresented: $showsDueDatePicker) {
            TaisaGraphicalDatePickerSheet(
                selection: draftDueDate,
                cancel: closeDueDatePicker,
                commit: { selected in
                    dueDate = selected
                    closeDueDatePicker()
                }
            )
        }
    }

    private func closeDueDatePicker() {
        showsDueDatePicker = false
        Task { @MainActor in
            await Task.yield()
            titleIsFocused = true
        }
    }

#if canImport(UIKit)
    private func keyboardEndFrame(from notification: Notification) -> CGRect {
        (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
    }
#endif
}

private extension Date {
    var taskComposerLabel: String {
        formatted(.dateTime.day().month(.abbreviated))
    }
}
