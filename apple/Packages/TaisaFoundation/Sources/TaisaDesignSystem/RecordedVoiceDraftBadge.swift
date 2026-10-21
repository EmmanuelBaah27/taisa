import SwiftUI

public struct RecordedVoiceDraftBadge: View {
    public enum Contract {
        public static let label = "Recorded"
        public static let iconSize: CGFloat = 20
    }

    private let elapsed: String

    public init(elapsed: String) { self.elapsed = elapsed }

    public var body: some View {
        HStack(spacing: TaisaSpacing.compact.rawValue) {
            CentralIcon(.voiceMid)
                .frame(width: Contract.iconSize, height: Contract.iconSize)
            Text(Contract.label)
                .font(TaisaTypography.navigationLabel.font)
            if !elapsed.isEmpty {
                Text(elapsed)
                    .font(TaisaTypography.metadata.font)
                    .foregroundStyle(TaisaColor.mutedForeground.color)
                    .monospacedDigit()
            }
        }
        .foregroundStyle(TaisaColor.foreground.color)
        .padding(.horizontal, TaisaSpacing.standard.rawValue)
        .frame(height: TaisaControlMetric.conversationRecordingControl)
        .background(TaisaColor.background.color, in: Capsule())
        .overlay { Capsule().stroke(TaisaColor.border.color, lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recorded voice draft, \(elapsed)")
    }
}
