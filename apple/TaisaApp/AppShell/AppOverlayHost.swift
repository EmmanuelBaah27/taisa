import SwiftUI
import TaisaDesignSystem

struct AppOverlayActions {
    private let presentAction: @MainActor (AnyView, AnyView) -> Void
    let dismiss: @MainActor () -> Void

    init(
        present: @escaping @MainActor (AnyView, AnyView) -> Void,
        dismiss: @escaping @MainActor () -> Void
    ) {
        presentAction = present
        self.dismiss = dismiss
    }

    @MainActor
    func present(backdrop: AnyView, content: AnyView) {
        presentAction(backdrop, content)
    }

    static let inactive = AppOverlayActions(present: { _, _ in }, dismiss: {})
}

private struct AppOverlayActionsKey: EnvironmentKey {
    static let defaultValue = AppOverlayActions.inactive
}

extension EnvironmentValues {
    var appOverlayActions: AppOverlayActions {
        get { self[AppOverlayActionsKey.self] }
        set { self[AppOverlayActionsKey.self] = newValue }
    }
}

private struct AppOverlayPresentation: Identifiable {
    let id = UUID()
    let backdrop: AnyView
    let content: AnyView
}

struct AppOverlayHost<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var overlayAccessibilityFocused: Bool
    @State private var presentation: AppOverlayPresentation?
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
                .ignoresSafeArea(presentation == nil ? [] : .keyboard, edges: .bottom)
                .accessibilityHidden(presentation != nil)
                .environment(
                    \.appOverlayActions,
                    AppOverlayActions(
                        present: { backdrop, content in
                            withAnimation(TaisaMotion.overlayEaseOut) {
                                presentation = AppOverlayPresentation(
                                    backdrop: backdrop,
                                    content: content
                                )
                            }
                        },
                        dismiss: dismissPresentation
                    )
                )

            if let presentation {
                presentation.backdrop
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .zIndex(1)

                presentation.content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(.isModal)
                    .accessibilityAction(.escape, dismissPresentation)
                    .accessibilityFocused($overlayAccessibilityFocused)
                    .onAppear { overlayAccessibilityFocused = true }
                    .transition(overlayTransition)
                    .zIndex(2)
            }
        }
    }

    private var overlayTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    private func dismissPresentation() {
        overlayAccessibilityFocused = false
        withAnimation(TaisaMotion.overlayEaseOut) {
            presentation = nil
        }
    }
}
