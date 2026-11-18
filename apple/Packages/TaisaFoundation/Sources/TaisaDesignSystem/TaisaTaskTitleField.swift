import SwiftUI

public struct TaisaTaskTitleField: View {
    @Binding private var text: String
    private let focus: FocusState<Bool>.Binding

    public init(text: Binding<String>, focus: FocusState<Bool>.Binding) {
        _text = text
        self.focus = focus
    }

    public var body: some View {
        TextField("Add task…", text: $text, axis: .vertical)
            .font(TaisaTypography.taskTitle.font)
            .tint(TaisaColor.foreground.color)
            .lineLimit(1...3)
            .focused(focus)
            .accessibilityLabel("Task title")
    }
}
