import SwiftUI

/// A data-derived fallback while photo editing and persistence remain deferred.
public struct TaisaProfileAvatar: View {
    private let name: String
    private let size: CGFloat
    public init(name: String, size: CGFloat = TaisaProfileMetric.avatar) {
        self.name = name; self.size = size
    }
    public var body: some View {
        let initials = name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        TaisaText(role: .profileBody, content: initials)
            .frame(width: size, height: size)
            .background(TaisaColor.subtleSurface.color, in: Circle())
            .accessibilityHidden(true)
    }
}

public struct TaisaProfileIconButton: View {
    private let icon: CentralIconName
    private let label: String
    private let action: @MainActor () -> Void
    public init(icon: CentralIconName, label: String, action: @escaping @MainActor () -> Void) {
        self.icon = icon; self.label = label; self.action = action
    }
    public var body: some View {
        TaisaSecondaryIconButton(
            icon: icon,
            accessibilityLabel: label,
            action: action
        )
    }
}

public struct TaisaProfileSummary: View {
    private let name: String
    private let bio: String
    private let edit: @MainActor () -> Void
    public init(name: String, bio: String, edit: @escaping @MainActor () -> Void) {
        self.name = name; self.bio = bio; self.edit = edit
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: TaisaProfileMetric.headerGap) {
            HStack(alignment: .top) {
                TaisaProfileAvatar(name: name)
                Spacer()
                TaisaProfileIconButton(icon: .profileEdit, label: "Edit profile", action: edit)
                    .frame(height: TaisaProfileMetric.avatar)
                    .accessibilityIdentifier("you.profile.edit")
            }
            TaisaText(role: .profileName, content: name.isEmpty ? "Your profile" : name)
                .frame(minHeight: TaisaProfileMetric.nameLineHeight, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if !bio.isEmpty {
                TaisaText(role: .profileSupporting, color: .mutedForeground, content: bio)
                    .frame(minHeight: TaisaTypography.supporting.lineHeight, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, TaisaSpacing.control.rawValue)
    }
}

public struct TaisaSettingsNavigationRow: View {
    private let title: String
    private let icon: CentralIconName
    private let action: @MainActor () -> Void
    public init(_ title: String, icon: CentralIconName, action: @escaping @MainActor () -> Void) {
        self.title = title; self.icon = icon; self.action = action
    }
    public var body: some View {
        TaisaButtonControl(action: action) {
            HStack(spacing: TaisaSpacing.control.rawValue) {
                CentralIcon(icon)
                    .frame(width: TaisaControlMetric.standardIcon, height: TaisaControlMetric.standardIcon)
                    .foregroundStyle(TaisaColor.mutedForeground.color)
                TaisaText(role: .profileLabel, content: title)
                    .frame(minHeight: TaisaTypography.navigationLabel.lineHeight, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                CentralIcon(.profileChevron)
                    .frame(width: TaisaProfileMetric.chevron, height: TaisaProfileMetric.chevron)
                    .foregroundStyle(TaisaColor.mutedForeground.color)
            }
            .padding(.horizontal, TaisaSpacing.standard.rawValue)
            .padding(.vertical, TaisaSpacing.control.rawValue)
            .frame(minHeight: TaisaControlMetric.primaryNavigationItemHeight)
            .background(TaisaColor.subtleSurface.color)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityHint("Opens \(title)")
    }
}

public struct TaisaSettingsGroup<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        VStack(spacing: TaisaProfileMetric.rowGap) { content }
            .background(TaisaColor.background.color)
            .clipShape(RoundedRectangle(cornerRadius: TaisaRadius.historyGroup.rawValue))
    }
}

public struct TaisaProfileSection<Content: View>: View {
    private let title: String
    private let content: Content
    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.content = content()
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: TaisaSpacing.control.rawValue) {
            TaisaText(role: .profileBody, content: title).accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TaisaSpacing.standard.rawValue)
        .background(TaisaColor.subtleSurface.color, in: RoundedRectangle(cornerRadius: TaisaRadius.historyGroup.rawValue))
    }
}
