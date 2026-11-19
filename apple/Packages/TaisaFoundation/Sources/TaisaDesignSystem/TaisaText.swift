import SwiftUI

public struct TaisaText: View {
    private let role: TaisaTypography
    private let color: TaisaColor
    private let content: String

    public init(
        role: TaisaTypography,
        color: TaisaColor = .foreground,
        content: String
    ) {
        self.role = role
        self.color = color
        self.content = content
    }

    /// Text-valued primitive for platform text renderers and attributed messages.
    public static func native(_ content: String, role: TaisaTypography = .body) -> Text {
        Text(content).font(role.font)
    }

    public static func native(_ content: AttributedString, role: TaisaTypography = .body) -> Text {
        Text(content).font(role.font)
    }

    public static func joining(_ first: Text, _ second: Text) -> Text {
        Text("\(first)\(second)")
    }

    public var body: some View {
        Text(content)
            .font(role.font)
            .lineSpacing(role.lineSpacing)
            .foregroundStyle(color.color)
    }
}

#Preview("Text roles") {
    VStack(alignment: .leading, spacing: TaisaSpacing.standard.rawValue) {
        TaisaText(role: .display, content: "Taisa")
        TaisaText(role: .heading, content: "Native foundation")
        TaisaText(role: .body, color: .mutedForeground, content: "Accessible by default")
    }
    .padding()
}
