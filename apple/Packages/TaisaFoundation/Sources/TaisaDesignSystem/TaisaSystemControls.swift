import SwiftUI

public struct TaisaPicker<Option: Hashable>: View {
    private let title: String
    private let options: [Option]
    private let label: (Option) -> String
    @Binding private var selection: Option

    public init(_ title: String, selection: Binding<Option>, options: [Option], label: @escaping (Option) -> String) {
        self.title = title
        _selection = selection
        self.options = options
        self.label = label
    }

    public var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.self) { option in Text(label(option)).tag(option) }
        }
        .tint(TaisaColor.foreground.color)
    }
}
public struct TaisaNavigationRow: View {
    private let label: String
    private let icon: CentralIconName?

    public init(label: String, icon: CentralIconName? = nil) {
        self.label = label
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: TaisaSpacing.control.rawValue) {
            if let icon { CentralIcon(icon).frame(width: 24, height: 24) }
            TaisaText(role: .body, content: label)
            Spacer()
            CentralIcon(.chevronLeft).rotationEffect(.degrees(180)).frame(width: 20, height: 20)
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}
