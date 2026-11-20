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
            ForEach(options, id: \.self) { option in TaisaText(role: .body, content: label(option)).tag(option) }
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

public struct TaisaSection<Content: View>: View {
    private let title: String
    private let content: Content
    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    public var body: some View {
        Section { content } header: { TaisaText(role: .label, content: title) }
    }
}

public struct TaisaLabeledContent: View {
    private let title: String
    private let value: String
    public init(_ title: String, value: String) { self.title = title; self.value = value }
    public var body: some View {
        HStack {
            TaisaText(role: .label, content: title)
            Spacer()
            TaisaText(role: .body, color: .mutedForeground, content: value)
        }
    }
}

public struct TaisaProgressView: View {
    private let title: String
    public init(_ title: String) { self.title = title }
    public var body: some View {
        ProgressView { TaisaText(role: .supporting, content: title) }
    }
}

public struct TaisaIconLabel: View {
    private let title: String
    private let icon: CentralIconName
    private let role: TaisaTypography
    public init(_ title: String, icon: CentralIconName, role: TaisaTypography = .label) {
        self.title = title; self.icon = icon; self.role = role
    }
    public var body: some View {
        HStack(spacing: TaisaSpacing.compact.rawValue) {
            CentralIcon(icon).frame(width: TaisaControlMetric.standardIcon, height: TaisaControlMetric.standardIcon)
            TaisaText(role: role, content: title)
        }
    }
}
