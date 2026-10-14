import Foundation

enum PrimaryDestination: String, CaseIterable, Hashable, Sendable {
    case home
    case careerWork
    case conversations
    case you

    var title: String {
        switch self {
        case .home: "Home"
        case .careerWork: "Career Work"
        case .conversations: "Conversations"
        case .you: "You"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .careerWork: "target"
        case .conversations: "bubble.left.and.bubble.right"
        case .you: "person"
        }
    }
}

enum ConversationEntryIntent: Sendable, Equatable {
    case voice
    case text
}

struct ConversationRoute: Identifiable, Sendable, Equatable {
    let id: String
    let localTitle: String
}
