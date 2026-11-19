import SwiftUI

/// A data-derived fallback while photo editing and persistence remain deferred.
public struct TaisaProfileAvatar: View {
    public enum Contract {
        public static let fallbackAsset = "ProfileAvatarFallback"
    }

    private let size: CGFloat
    public init(size: CGFloat = TaisaProfileMetric.avatar) {
        self.size = size
    }
    public var body: some View {
        Image(Contract.fallbackAsset, bundle: .module)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}

public struct TaisaProfileIconButton: View {
    public enum Contract {
        public static let minimumTarget = TaisaControlMetric.headerActionHeight
    }

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
    public enum Contract {
        public static func displayName(for name: String) -> String {
            name.isEmpty ? "Your profile" : name
        }

        public static func displaysBio(_ bio: String) -> Bool { !bio.isEmpty }
    }

    private let name: String
    private let bio: String
    private let edit: @MainActor () -> Void
    public init(name: String, bio: String, edit: @escaping @MainActor () -> Void) {
        self.name = name; self.bio = bio; self.edit = edit
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: TaisaProfileMetric.headerGap) {
            HStack(alignment: .top) {
                TaisaProfileAvatar()
                Spacer()
                TaisaProfileIconButton(icon: .profileEdit, label: "Edit profile", action: edit)
                    .frame(height: TaisaProfileMetric.avatar)
                    .accessibilityIdentifier("you.profile.edit")
            }
            TaisaText(role: .profileName, content: Contract.displayName(for: name))
                .frame(minHeight: TaisaProfileMetric.nameLineHeight, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if Contract.displaysBio(bio) {
                TaisaText(role: .profileSupporting, color: .mutedForeground, content: bio)
                    .frame(minHeight: TaisaTypography.supporting.lineHeight, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, TaisaSpacing.control.rawValue)
    }
}

public struct TaisaSettingsNavigationRow: View {
    public enum Contract {
        public static let chevron = CentralIconName.profileChevron
        public static func hint(for title: String) -> String { "Opens \(title)" }
    }

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
                CentralIcon(Contract.chevron)
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
        .accessibilityHint(Contract.hint(for: title))
    }
}

public struct TaisaSettingsGroup<Content: View>: View {
    public enum Contract {
        public static var radius: CGFloat { TaisaRadius.historyGroup.rawValue }
    }

    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        VStack(spacing: TaisaProfileMetric.rowGap) { content }
            .background(TaisaColor.background.color)
            .clipShape(RoundedRectangle(cornerRadius: Contract.radius))
    }
}

public struct TaisaProfileSection<Content: View>: View {
    public enum Contract {
        public static var radius: CGFloat { TaisaRadius.historyGroup.rawValue }
    }

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
        .background(TaisaColor.subtleSurface.color, in: RoundedRectangle(cornerRadius: Contract.radius))
    }
}
