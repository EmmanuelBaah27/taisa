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
    private let trailingIcon: CentralIconName
    private let action: (@MainActor () -> Void)?

    public init(
        label: String,
        icon: CentralIconName? = nil,
        trailingIcon: CentralIconName = .chevronLeft,
        action: (@MainActor () -> Void)? = nil
    ) {
        self.label = label
        self.icon = icon
        self.trailingIcon = trailingIcon
        self.action = action
    }

    @ViewBuilder
    public var body: some View {
        if let action {
            TaisaPressable(action: { action() }) { rowContent }
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: TaisaSpacing.control.rawValue) {
            if let icon {
                CentralIcon(icon)
                    .foregroundStyle(TaisaColor.inactiveForeground.color)
                    .frame(width: 24, height: 24)
            }
            TaisaText(role: .body, content: label)
            Spacer()
            CentralIcon(trailingIcon)
                .foregroundStyle(TaisaColor.inactiveForeground.color)
                .rotationEffect(.degrees(Self.trailingIconRotationDegrees(trailingIcon)))
                .frame(width: 20, height: 20)
        }
        .frame(maxWidth: .infinity, minHeight: TaisaButtonSize.standard.minimumHeight)
        .padding(.horizontal, TaisaSpacing.standard.rawValue)
        .background(TaisaColor.subtleSurface.color, in: rowShape)
        .contentShape(Rectangle())
    }

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: TaisaRadius.listInterior.rawValue)
    }

    static func trailingIconRotationDegrees(_ icon: CentralIconName) -> Double {
        icon == .chevronLeft ? 180 : 0
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
