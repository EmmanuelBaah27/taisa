import SwiftUI
import TaisaDesignSystem
import TaisaHome
import TaisaStorage

struct CompletionEvidenceSheet: View {
    let item: WeeklyWorkItem
    let model: HomeModel
    @State private var evidenceTitle = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Completion evidence") {
                    TaisaField("What shows this is complete?", text: $evidenceTitle, placeholder: "Describe the delivered result")
                    TaisaButton(role: .primary, label: "Complete action", icon: .completeAction, isEnabled: !trimmedEvidence.isEmpty) {
                        let evidence = trimmedEvidence
                        Task { await model.complete(actionID: item.action.id, evidenceTitle: evidence); dismiss() }
                    }
                }
            }
            .navigationTitle(item.action.title)
            .accessibilityIdentifier("home.this-week.completion-evidence")
        }
    }

    private var trimmedEvidence: String { evidenceTitle.trimmingCharacters(in: .whitespacesAndNewlines) }
}

enum HomeIntent: Sendable, Equatable {
    case conversation(String)
    case goal(String)
    case action(String)
    case milestone(goalID: String)
}

struct MilestoneRow: View {
    let milestone: MilestoneRecord
    let send: (HomeIntent) -> Void

    var body: some View {
        Button { send(.milestone(goalID: milestone.goalID)) } label: {
            HStack {
                Image(systemName: "flag")
                VStack(alignment: .leading) {
                    Text(milestone.title)
                    if let targetAtMS = milestone.targetAtMS {
                        Text(Date(timeIntervalSince1970: Double(targetAtMS) / 1_000), format: .dateTime.day().month())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
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
            TaisaRow(title: action.title, supporting: action.dueDay.map { "Due \($0.rawValue)" }, icon: .action)
        }
    }
}
