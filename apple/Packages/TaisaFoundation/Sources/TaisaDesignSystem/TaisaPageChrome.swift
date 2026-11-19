import SwiftUI

public enum TaisaBottomChromeContract {
    public static let fadeHeight = TaisaControlMetric.primaryNavigationReservedHeight
    public static let coversBottomSafeArea = true
}
/// Shared bottom chrome for primary destinations.
///
/// Place this component in a root `safeAreaInset(edge: .bottom)` so its fade
/// owns the home-indicator region and its height reserves scrolling content.
public struct TaisaBottomChrome<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: TaisaBottomChromeContract.fadeHeight, alignment: .bottom)
            .background {
                PageEdgeFade(.navigation)
                    .ignoresSafeArea(edges: [.horizontal, .bottom])
                    .allowsHitTesting(false)
            }
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
            TaisaText(role: .datedPageTitle, color: .foreground, content: title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("taisa.page-title")

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
public struct TaisaDatedPageHeader<Actions: View>: View {
    private let date: String
    private let title: String
    private let actions: Actions

    public init(date: String, title: String, @ViewBuilder actions: () -> Actions) {
        self.date = date
        self.title = title
        self.actions = actions()
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: TaisaSpacing.standard.rawValue) {
            VStack(alignment: .leading, spacing: TaisaTaskSpacing.headerGap) {
                TaisaText(role: .taskSupporting, color: .mutedForeground, content: date)
                TaisaText(role: .datedPageTitle, content: title)
            }
            Spacer(minLength: 0)
            actions
        }
        .padding(.horizontal, TaisaSpacing.content.rawValue)
        .padding(.vertical, TaisaSpacing.control.rawValue)
        .frame(height: TaisaControlMetric.taskHeaderHeight)
        .background(TaisaColor.background.color)
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
            TaisaText(role: .childHeaderTitle, content: title)
                .lineLimit(1)
                .accessibilityIdentifier("taisa.child-page-title")

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

private struct TaisaNavigationTitleModifier: ViewModifier {
    let title: String

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(iOS)
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TaisaText(role: .childHeaderTitle, color: .foreground, content: title)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                        .accessibilityRepresentation {
                            EmptyView()
                        }
                }
            }
#else
        content.navigationTitle(title)
#endif
    }
}

public extension View {
    /// Keeps native navigation metadata and Back behavior while rendering the
    /// visible title through Taisa's semantic typography contract.
    func taisaNavigationTitle(_ title: String) -> some View {
        modifier(TaisaNavigationTitleModifier(title: title))
    }
}

/// Shared bottom backdrop and safe-area treatment for the open-chat composer.
public struct ConversationComposerChrome<Content: View, Backdrop: View>: View {
    private let content: Content
    private let backdrop: Backdrop

    public init(@ViewBuilder content: () -> Content) where Backdrop == PageEdgeFade {
        self.content = content()
        backdrop = PageEdgeFade(.navigation)
    }

    public init(
        @ViewBuilder backdrop: () -> Backdrop,
        @ViewBuilder content: () -> Content
    ) {
        self.backdrop = backdrop()
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, TaisaSpacing.standard.rawValue)
            .padding(.vertical, TaisaSpacing.section.rawValue)
            .frame(minHeight: TaisaControlMetric.conversationComposerDockHeight, alignment: .bottom)
            .background(alignment: .bottom) {
                backdrop
                    .ignoresSafeArea(edges: [.horizontal, .bottom])
                    .allowsHitTesting(false)
            }
    }
}
