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

public struct TaisaExpandableSheet<Content: View>: View {
    @State private var selectedDetent: PresentationDetent = .medium
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .presentationDetents([.medium, .large], selection: $selectedDetent)
            .presentationDragIndicator(.visible)
            .presentationBackground(TaisaColor.background.color)
    }
}
