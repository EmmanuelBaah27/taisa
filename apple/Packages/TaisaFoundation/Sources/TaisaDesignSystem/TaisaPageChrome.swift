import SwiftUI

public enum TaisaBottomChromeContract {
    public static let fadeHeight = TaisaControlMetric.primaryNavigationReservedHeight
    public static let coversBottomSafeArea = true
}

/// Owns the continuous fade and system-safe-area background behind bottom controls.
public struct TaisaBottomChrome<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            PageEdgeFade(.navigation)
                .frame(maxWidth: .infinity)
                .frame(height: TaisaBottomChromeContract.fadeHeight)
                .ignoresSafeArea(edges: [.horizontal, .bottom])
                .allowsHitTesting(false)

            content
        }
        .frame(maxWidth: .infinity)
    }
}

/// Shared top chrome for the primary Home, Chats, and You destinations.
public struct TaisaPageHeader<Actions: View>: View {
    private let title: String
    private let actions: Actions

    public init(
        _ title: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.actions = actions()
    }

    public var body: some View {
        HStack(spacing: TaisaSpacing.standard.rawValue) {
            Text(title)
                .font(.system(.title, weight: .semibold))
                .foregroundStyle(TaisaColor.foreground.color)
                .frame(maxWidth: .infinity, alignment: .leading)

            actions
        }
        .padding(.horizontal, TaisaSpacing.standard.rawValue)
        .frame(height: TaisaControlMetric.appBarHeight)
        .background {
            PageEdgeFade(.header)
                .ignoresSafeArea(edges: [.top, .horizontal])
        }
    }
}

/// Shared top chrome for pages pushed within a primary destination.
public struct TaisaChildPageHeader: View {
    public enum Mode: Sendable {
        case back
        case detail
    }

    private let title: String
    private let mode: Mode
    private let back: @MainActor () -> Void

    public init(
        _ title: String,
        mode: Mode = .back,
        back: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.mode = mode
        self.back = back
    }

    public var body: some View {
        ZStack {
            Text(title)
                .font(.system(.headline, weight: .semibold))
                .foregroundStyle(TaisaColor.foreground.color)
                .lineLimit(1)

            HStack {
                if mode == .back {
                    TaisaSecondaryIconButton(
                        icon: .chevronLeft,
                        accessibilityLabel: "Back",
                        size: TaisaControlMetric.childNavigationControlHeight,
                        action: back
                    )
                }
                Spacer()
            }
        }
        .padding(.horizontal, TaisaSpacing.standard.rawValue)
        .frame(height: TaisaControlMetric.appBarHeight)
        .background {
            PageEdgeFade(.header)
                .ignoresSafeArea(edges: [.top, .horizontal])
        }
    }
}

/// Shared bottom fade and safe-area treatment for the open-chat composer.
public struct ConversationComposerChrome<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, TaisaSpacing.standard.rawValue)
            .padding(.vertical, TaisaSpacing.section.rawValue)
            .frame(minHeight: TaisaControlMetric.conversationComposerDockHeight, alignment: .bottom)
            .background {
                PageEdgeFade(.navigation)
                    .ignoresSafeArea(edges: [.horizontal, .bottom])
                    .allowsHitTesting(false)
            }
    }
}

/// The shared circular secondary action used in primary page headers.
public struct TaisaSecondaryIconButton: View {
    private let icon: CentralIconName
    private let accessibilityLabel: String
    private let accessibilityHint: String?
    private let size: CGFloat
    private let action: @MainActor () -> Void

    public init(
        icon: CentralIconName,
        accessibilityLabel: String,
        accessibilityHint: String? = nil,
        size: CGFloat = TaisaControlMetric.headerActionHeight,
        action: @escaping @MainActor () -> Void
    ) {
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.size = size
        self.action = action
    }

    public var body: some View {
        secondaryGlassButton
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint ?? "")
    }

    @ViewBuilder private var secondaryGlassButton: some View {
        let button = Button(action: action) {
            CentralIcon(icon)
                .frame(
                    width: TaisaControlMetric.standardIcon,
                    height: TaisaControlMetric.standardIcon
                )
                .frame(
                    width: size,
                    height: size
                )
        }

        if #available(iOS 26.0, macOS 26.0, *) {
            button
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .contentShape(Circle())
        } else {
            button
                .buttonStyle(.plain)
                .background(.regularMaterial, in: Circle())
                .contentShape(Circle())
        }
    }
}

/// The shared capsule secondary action used in primary page headers.
public struct TaisaSecondaryCapsuleButton<Label: View>: View {
    private let action: @MainActor () -> Void
    private let label: Label
    private let height: CGFloat

    public init(
        height: CGFloat = TaisaControlMetric.headerActionHeight,
        action: @escaping @MainActor () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.height = height
        self.action = action
        self.label = label()
    }

    public var body: some View {
        secondaryGlassButton
    }

    @ViewBuilder private var secondaryGlassButton: some View {
        let button = Button(action: action) {
            label
                .frame(height: height)
        }

        if #available(iOS 26.0, macOS 26.0, *) {
            button
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Capsule())
                .contentShape(Capsule())
        } else {
            button
                .buttonStyle(.plain)
                .background(.regularMaterial, in: Capsule())
                .contentShape(Capsule())
        }
    }
}
