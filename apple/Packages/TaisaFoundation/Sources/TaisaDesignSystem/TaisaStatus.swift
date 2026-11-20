import SwiftUI

public enum TaisaStatusRole: Sendable, Equatable {
    case active
    case completed
    case dropped
    case overdue
    case reopened
    case warning

    var icon: CentralIconName {
        switch self {
        case .active: .incomplete
        case .completed: .completed
        case .dropped: .drop
        case .overdue, .warning: .warning
        case .reopened: .undo
        }
    }

    var color: TaisaColor {
        switch self {
        case .overdue, .warning: .warning
        case .dropped: .mutedForeground
        default: .foreground
        }
    }
}

public struct TaisaStatusMark: View {
    private let role: TaisaStatusRole
    public init(_ role: TaisaStatusRole) { self.role = role }
    public var body: some View {
        CentralIcon(role.icon).frame(width: 24, height: 24).foregroundStyle(role.color.color)
    }
}

public struct TaisaStatusSurface: View {
    private let role: TaisaStatusRole
    private let label: String
    public init(_ role: TaisaStatusRole, label: String) { self.role = role; self.label = label }
    public var body: some View {
        HStack(spacing: TaisaSpacing.compact.rawValue) {
            TaisaStatusMark(role)
            TaisaText(role: .metadata, color: role.color, content: label)
        }
        .padding(.horizontal, TaisaSpacing.control.rawValue)
        .padding(.vertical, TaisaSpacing.compact.rawValue)
        .background(TaisaColor.subtleSurface.color, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
