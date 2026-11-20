import SwiftUI

public struct TaisaInformationSheetPolicy: Sendable, Equatable {
    public static let `default` = Self()
    public let blocksInteractiveDismissal = false

    public init() {}
}

public struct TaisaEditorSheetPolicy: Sendable, Equatable {
    public let isDirty: Bool
    public let isBusy: Bool

    public init(isDirty: Bool, isBusy: Bool) {
        self.isDirty = isDirty
        self.isBusy = isBusy
    }

    public var blocksInteractiveDismissal: Bool { isDirty || isBusy }
    public func keepsContentMounted(after result: TaisaPresentationResult) -> Bool {
        !result.shouldDismiss
    }
}

public struct TaisaTaskSheetPolicy: Sendable, Equatable {
    public let isBusy: Bool

    public init(isBusy: Bool) { self.isBusy = isBusy }

    public var blocksInteractiveDismissal: Bool { isBusy }
    public func keepsContentMounted(after result: TaisaPresentationResult) -> Bool {
        !result.shouldDismiss
    }
}

public struct TaisaInformationSheet<Content: View>: View {
    private let title: String
    private let done: @MainActor () -> Void
    private let content: Content

    public init(title: String, done: @escaping @MainActor () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.done = done
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            TaisaPresentationNavigation(title: title) {
                Spacer().frame(width: 1, height: 1)
            } trailing: {
                TaisaButton(role: .ghost, label: "Done", size: .small, layout: .intrinsic, action: done)
            }
            content
        }
    }
}

public struct TaisaEditorSheet<Content: View>: View {
    private let title: String
    private let policy: TaisaEditorSheetPolicy
    private let canSave: Bool
    private let cancel: @MainActor () -> Void
    private let save: @MainActor () -> Void
    private let content: Content

    public init(
        title: String,
        isDirty: Bool,
        isBusy: Bool,
        canSave: Bool,
        cancel: @escaping @MainActor () -> Void,
        save: @escaping @MainActor () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        policy = TaisaEditorSheetPolicy(isDirty: isDirty, isBusy: isBusy)
        self.canSave = canSave
        self.cancel = cancel
        self.save = save
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            TaisaPresentationNavigation(title: title) {
                TaisaButton(role: .ghost, label: "Cancel", size: .small, layout: .intrinsic, isEnabled: !policy.isBusy, action: cancel)
            } trailing: {
                TaisaButton(role: .primary, label: "Save", size: .small, layout: .intrinsic, isEnabled: canSave && !policy.isBusy, isProcessing: policy.isBusy, action: save)
            }
            content
        }
        .interactiveDismissDisabled(policy.blocksInteractiveDismissal)
    }
}

public struct TaisaTaskSheet<Content: View>: View {
    private let title: String
    private let action: TaisaPresentationAction
    private let cancel: (@MainActor () -> Void)?
    private let perform: @MainActor () -> Void
    private let content: Content

    public init(
        title: String,
        action: TaisaPresentationAction,
        cancel: (@MainActor () -> Void)? = nil,
        perform: @escaping @MainActor () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.action = action
        self.cancel = cancel
        self.perform = perform
        self.content = content()
    }

    public var body: some View {
        let policy = TaisaTaskSheetPolicy(isBusy: action.isBusy)
        VStack(spacing: 0) {
            TaisaPresentationNavigation(title: title) {
                if let cancel {
                    TaisaButton(role: .ghost, label: "Cancel", size: .small, layout: .intrinsic, isEnabled: !action.isBusy, action: cancel)
                }
            } trailing: {
                TaisaButton(
                    role: action.role == .destructive ? .destructive : .primary,
                    label: action.label,
                    size: .small,
                    layout: .intrinsic,
                    isEnabled: action.canInvoke,
                    isProcessing: action.isBusy,
                    action: perform
                )
                .accessibilityIdentifier(action.accessibilityIdentifier ?? "")
            }
            content
        }
        .interactiveDismissDisabled(policy.blocksInteractiveDismissal)
    }
}
