import SwiftUI

public enum TaisaTaskTitleFieldContract {
    public static let characterLimit = 120

    public static func limited(_ value: String) -> String {
        String(value.prefix(characterLimit))
    }
}

public struct TaisaTaskTitleField: View {
    @Binding private var text: String
    private let focus: FocusState<Bool>.Binding

    public init(text: Binding<String>, focus: FocusState<Bool>.Binding) {
        _text = text
        self.focus = focus
    }

    public var body: some View {
        TextField(
            "Add task…",
            text: Binding(
                get: { text },
                set: { text = TaisaTaskTitleFieldContract.limited($0) }
            ),
            axis: .vertical
        )
            .font(TaisaTypography.taskTitle.font)
            .tint(TaisaColor.foreground.color)
            .lineLimit(1...3)
            .focused(focus)
            .accessibilityLabel("Task title")
    }
}
