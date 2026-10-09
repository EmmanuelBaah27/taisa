import SwiftUI
import TaisaStorage

enum HomeIntent: Sendable, Equatable {
    case conversation(String)
    case goal(String)
    case action(String)
}

struct ConversationRow: View {
    let conversation: ConversationRecord
    let send: (HomeIntent) -> Void

    var body: some View {
        Button { send(.conversation(conversation.id)) } label: {
            Label(conversation.title, systemImage: "bubble.left.and.bubble.right")
        }
    }
}

struct GoalRow: View {
    let goal: GoalRecord
    let send: (HomeIntent) -> Void

    var body: some View {
        Button { send(.goal(goal.id)) } label: {
            VStack(alignment: .leading) {
                Text(goal.title)
                if !goal.detail.isEmpty { Text(goal.detail).font(.subheadline).foregroundStyle(.secondary) }
            }
        }
    }
}

struct ActionRow: View {
    let action: ActionRecord
    let send: (HomeIntent) -> Void

    var body: some View {
        Button { send(.action(action.id)) } label: {
            HStack {
                Image(systemName: "circle")
                VStack(alignment: .leading) {
                    Text(action.title)
                    if let dueAtMS = action.dueAtMS {
                        Text(Date(timeIntervalSince1970: Double(dueAtMS) / 1_000), format: .dateTime.day().month())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
