import SwiftUI

public enum TaisaRowEmphasis: Sendable, Equatable {
    case standard
    case attention
}

public struct TaisaRow: View {
    private let title: String
    private let supporting: String?
    private let metadata: String?
    private let icon: CentralIconName?
    private let emphasis: TaisaRowEmphasis
    private let action: (@MainActor () -> Void)?

    public init(
        title: String,
        supporting: String? = nil,
        metadata: String? = nil,
        icon: CentralIconName? = nil,
        emphasis: TaisaRowEmphasis = .standard,
        action: (@MainActor () -> Void)? = nil
    ) {
        self.title = title
        self.supporting = supporting
        self.metadata = metadata
        self.icon = icon
        self.emphasis = emphasis
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
        HStack(alignment: .top, spacing: TaisaSpacing.control.rawValue) {
            if let icon {
                CentralIcon(icon).frame(width: 24, height: 24)
            }
            VStack(alignment: .leading, spacing: TaisaSpacing.tight.rawValue) {
                TaisaText(role: .body, content: title)
                if let supporting { TaisaText(role: .supporting, color: .mutedForeground, content: supporting) }
                if let metadata { TaisaText(role: .metadata, color: .mutedForeground, content: metadata) }
            }
            Spacer(minLength: 0)
        }
        .padding(TaisaSpacing.standard.rawValue)
        .background(emphasis == .attention ? TaisaColor.subtleSurface.color : TaisaColor.background.color)
        .clipShape(RoundedRectangle(cornerRadius: TaisaRadius.control.rawValue))
    }
}
