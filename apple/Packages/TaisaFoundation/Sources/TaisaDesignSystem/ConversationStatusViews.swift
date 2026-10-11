import SwiftUI

public struct ConversationProgressState: View {
    public let label: String
    public init(label: String) { self.label = label }
    public var body: some View { HStack { ProgressView(); Text(label) }.accessibilityElement(children: .combine) }
}

public struct ConversationFailureActions: View {
    public struct Contract: Sendable, Equatable {
        public let retryLabel: String
        public static let retryable = Contract(retryLabel: "Retry request")
    }
    let message: String
    let onRetry: @MainActor () -> Void
    let onSave: @MainActor () -> Void
    let onDiscard: @MainActor () -> Void
    public init(message: String, onRetry: @escaping @MainActor () -> Void, onSave: @escaping @MainActor () -> Void, onDiscard: @escaping @MainActor () -> Void) {
        self.message = message; self.onRetry = onRetry; self.onSave = onSave; self.onDiscard = onDiscard
    }
    public var body: some View {
        VStack { Text(message); Button(Contract.retryable.retryLabel, action: onRetry); Button("Save draft", action: onSave); Button("Discard", role: .destructive, action: onDiscard) }
    }
}
