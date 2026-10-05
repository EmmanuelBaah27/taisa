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

    public var body: some View {
        Text(content)
            .font(role.font)
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
