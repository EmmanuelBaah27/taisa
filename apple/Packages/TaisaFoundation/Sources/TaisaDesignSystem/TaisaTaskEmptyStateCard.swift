import SwiftUI

public struct TaisaTaskEmptyStateCard: View {
    private let action: @MainActor @Sendable () -> Void

    public init(action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action
    }

    public var body: some View {
        VStack(spacing: TaisaSpacing.control.rawValue) {
            CentralIcon(.planning)
                .frame(width: TaisaControlMetric.standardIcon, height: TaisaControlMetric.standardIcon)
                .foregroundStyle(TaisaColor.mutedForeground.color)

            TaisaText(
                role: .body,
                color: .mutedForeground,
                content: "Start organising and tracking work"
            )
            .multilineTextAlignment(.center)

            TaisaButton(
                role: .secondary,
                shape: .capsule,
                label: "Add a task",
                icon: .add,
                size: .small,
                layout: .intrinsic,
                action: action
            )
            .accessibilityLabel("Add task")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, TaisaSpacing.standard.rawValue)
        .padding(.vertical, TaisaSpacing.section.rawValue)
        .background(TaisaColor.subtleSurface.color)
        .overlay {
            RoundedRectangle(cornerRadius: TaisaRadius.taskGroup)
                .stroke(TaisaColor.background.color, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: TaisaRadius.taskGroup))
    }
}
