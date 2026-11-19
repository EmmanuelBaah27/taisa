import SwiftUI
import TaisaDesignSystem
import TaisaHome
import TaisaStorage

enum HomeIntent: Sendable, Equatable {
    case conversation(String)
    case goal(String)
    case action(String)
    case milestone(goalID: String)
    case actions
    case goals
}

struct MilestoneRow: View {
    let milestone: MilestoneRecord
    let send: (HomeIntent) -> Void

    var body: some View {
        TaisaPressable(action: { send(.milestone(goalID: milestone.goalID)) }) {
            TaisaRow(
                title: milestone.title,
                supporting: milestone.targetAtMS.map {
                    Date(timeIntervalSince1970: Double($0) / 1_000).formatted(.dateTime.day().month())
                },
                icon: .milestone
            )
        }
    }
}

struct ConversationRow: View {
    let conversation: ConversationRecord
    let send: (HomeIntent) -> Void

    var body: some View {
        TaisaPressable(action: { send(.conversation(conversation.id)) }) {
            TaisaRow(title: conversation.title, icon: .chatBubbles)
        }
    }
}

struct GoalRow: View {
    let goal: GoalRecord
    let send: (HomeIntent) -> Void

    var body: some View {
        TaisaPressable(action: { send(.goal(goal.id)) }) {
            TaisaRow(title: goal.title, supporting: goal.detail.isEmpty ? nil : goal.detail, icon: .goal)
        }
    }
}

struct ActionRow: View {
    let action: ActionRecord
    let send: (HomeIntent) -> Void

    var body: some View {
        TaisaPressable(action: { send(.action(action.id)) }) {
            TaisaRow(title: action.title, supporting: action.dueDay.map { "Due \($0.rawValue)" }, icon: .action)
        }
    }
}
