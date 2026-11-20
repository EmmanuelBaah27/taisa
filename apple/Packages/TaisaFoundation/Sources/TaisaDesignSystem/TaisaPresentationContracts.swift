import SwiftUI

public enum TaisaPresentationResult: Sendable, Equatable {
    case success
    case failure
    case cancelled

    public var shouldDismiss: Bool { self == .success }
}

public enum TaisaPresentationActionRole: Sendable, Equatable {
    case cancel
    case primary
    case destructive
}

public struct TaisaPresentationAction: Sendable, Equatable {
    public let label: String
    public let role: TaisaPresentationActionRole
    public let isEnabled: Bool
    public let isBusy: Bool
    public let accessibilityIdentifier: String?

    public init(
        label: String,
        role: TaisaPresentationActionRole,
        isEnabled: Bool = true,
        isBusy: Bool = false,
        accessibilityIdentifier: String? = nil
    ) {
        self.label = label
        self.role = role
        self.isEnabled = isEnabled
        self.isBusy = isBusy
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    public var canInvoke: Bool { isEnabled && !isBusy }
}

public struct TaisaPresentationActionButton: View {
    private let action: TaisaPresentationAction
    private let perform: @MainActor () -> Void

    public init(_ action: TaisaPresentationAction, perform: @escaping @MainActor () -> Void) {
        self.action = action
        self.perform = perform
    }

    public var body: some View {
        TaisaButtonControl(
            role: nativeRole,
            style: TaisaButtonStyle(role: .ghost, size: .small),
            action: perform
        ) {
            TaisaText(role: .buttonLabel, content: action.label)
        }
        .disabled(!action.canInvoke)
        .accessibilityIdentifier(action.accessibilityIdentifier ?? "")
    }

    private var nativeRole: ButtonRole? {
        switch action.role {
        case .cancel: .cancel
        case .primary: nil
        case .destructive: .destructive
        }
    }
}

@MainActor
public final class TaisaPresentationActionGate {
    public private(set) var isBusy = false

    public init() {}

    public func begin(isEnabled: Bool) -> Bool {
        guard isEnabled, !isBusy else { return false }
        isBusy = true
        return true
    }

    public func finish(with result: TaisaPresentationResult) -> Bool {
        guard isBusy else { return false }
        isBusy = false
        return result.shouldDismiss
    }
}

public struct TaisaPresentationNavigation<Leading: View, Trailing: View>: View {
    private let title: String
    private let leading: Leading
    private let trailing: Trailing

    public init(
        title: String,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: TaisaSpacing.standard.rawValue) {
            leading.frame(maxWidth: .infinity, alignment: .leading)
            TaisaText(role: .buttonLabel, content: title).lineLimit(1)
            trailing.frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minHeight: TaisaControlMetric.appBarHeight)
        .padding(.horizontal, TaisaSpacing.standard.rawValue)
    }
}
