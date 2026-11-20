import SwiftUI

public enum TaisaNativeDialogKind: Sendable, Equatable {
    case confirmation
    case textEntry
}

public struct TaisaConfirmationDialogPolicy: Sendable, Equatable {
    public static let destructive = Self()
    public let kind: TaisaNativeDialogKind = .confirmation

    public init() {}
}

public struct TaisaTextEntryAlertPolicy: Sendable, Equatable {
    public static let standard = Self()
    public let kind: TaisaNativeDialogKind = .textEntry

    public init() {}

    public func keepsTextMounted(after result: TaisaPresentationResult) -> Bool {
        !result.shouldDismiss
    }
}

public struct TaisaNativeConfirmationDialog<Actions: View, Message: View>: ViewModifier {
    @Binding private var isPresented: Bool
    private let title: String
    private let actions: Actions
    private let message: Message

    public init(
        title: String,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder message: () -> Message
    ) {
        self.title = title
        _isPresented = isPresented
        self.actions = actions()
        self.message = message()
    }

    public func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: $isPresented) {
            actions
        } message: {
            message
        }
    }
}

public struct TaisaTextEntryAlert<Actions: View, Message: View>: ViewModifier {
    @Binding private var isPresented: Bool
    @Binding private var text: String
    private let title: String
    private let prompt: String
    private let actions: Actions
    private let message: Message

    public init(
        title: String,
        prompt: String,
        text: Binding<String>,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder message: () -> Message
    ) {
        self.title = title
        self.prompt = prompt
        _text = text
        _isPresented = isPresented
        self.actions = actions()
        self.message = message()
    }

    public func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            TextField(prompt, text: $text)
            actions
        } message: {
            message
        }
    }
}
