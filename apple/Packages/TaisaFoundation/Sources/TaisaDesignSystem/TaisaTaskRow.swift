import SwiftUI

public enum TaisaTaskRowContract {
    public static let titleLineLimit = 2
}

public struct TaisaTaskRow: View {
    private let title: String
    private let dueLabel: String?

    public init(title: String, dueLabel: String? = nil) {
        self.title = title
        self.dueLabel = dueLabel
    }

    public var body: some View {
        HStack(alignment: dueLabel == nil ? .center : .top, spacing: TaisaSpacing.control.rawValue) {
            CentralIcon(.incomplete)
                .frame(width: TaisaControlMetric.standardIcon, height: TaisaControlMetric.standardIcon)
            VStack(alignment: .leading, spacing: TaisaTaskSpacing.headerGap) {
                TaisaText(role: .taskTitle, content: title)
                    .lineLimit(TaisaTaskRowContract.titleLineLimit)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(title)
                if let dueLabel {
                    HStack(spacing: TaisaTaskSpacing.dueGap) {
                        CentralIcon(.calendar)
                            .frame(width: TaisaControlMetric.taskDueIcon, height: TaisaControlMetric.taskDueIcon)
                        TaisaText(role: .taskSupporting, color: .mutedForeground, content: dueLabel)
                    }
                }
            }
        }
        .padding(.horizontal, TaisaSpacing.standard.rawValue)
        .padding(.vertical, TaisaSpacing.control.rawValue)
        .background(TaisaColor.subtleSurface.color)
    }
}

public struct TaisaTaskSummaryRow: View {
    private let count: Int
    public init(count: Int) { self.count = count }

    public var body: some View {
        HStack(spacing: TaisaSpacing.control.rawValue) {
            TaisaText(role: .taskTitle, color: .mutedForeground, content: "\(count)")
                .frame(width: TaisaControlMetric.standardIcon)
            TaisaText(role: .taskTitle, content: "View all tasks").frame(maxWidth: .infinity, alignment: .leading)
            CentralIcon(.chevronRight)
                .frame(width: TaisaControlMetric.compactActionIcon, height: TaisaControlMetric.compactActionIcon)
        }
        .padding(.horizontal, TaisaSpacing.standard.rawValue)
        .padding(.vertical, TaisaSpacing.control.rawValue)
        .background(TaisaColor.background.color)
        .clipShape(RoundedRectangle(cornerRadius: TaisaRadius.taskGroup))
        .overlay { RoundedRectangle(cornerRadius: TaisaRadius.taskGroup).stroke(TaisaColor.border.color) }
    }
}
