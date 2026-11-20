import SwiftUI

public enum TaisaExpandableSheetPosition: Sendable, Equatable {
    case medium
    case large
}

public enum TaisaExpandableSheetContract {
    public static let initialPosition = TaisaExpandableSheetPosition.medium
    public static let positions: [TaisaExpandableSheetPosition] = [.medium, .large]
    public static let showsDragIndicator = true
}

public struct TaisaExpandableSheetActions: Sendable {
    public let expand: @MainActor @Sendable () -> Void

    public init(expand: @escaping @MainActor @Sendable () -> Void) {
        self.expand = expand
    }
}

private struct TaisaExpandableSheetActionsKey: EnvironmentKey {
    static let defaultValue = TaisaExpandableSheetActions(expand: {})
}

public extension EnvironmentValues {
    var taisaExpandableSheetActions: TaisaExpandableSheetActions {
        get { self[TaisaExpandableSheetActionsKey.self] }
        set { self[TaisaExpandableSheetActionsKey.self] = newValue }
    }
}

public struct TaisaExpandableSheet<Content: View>: View {
    @State private var selectedDetent: PresentationDetent = .medium
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .environment(
                \.taisaExpandableSheetActions,
                TaisaExpandableSheetActions(expand: { selectedDetent = .large })
            )
            .presentationDetents([.medium, .large], selection: $selectedDetent)
            .presentationDragIndicator(.visible)
            .presentationBackground(TaisaColor.background.color)
    }
}
