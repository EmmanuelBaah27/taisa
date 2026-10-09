import Foundation

enum PrimaryDestination: String, CaseIterable, Hashable, Sendable {
    case home
    case conversations
    case you

    var title: String {
        switch self {
        case .home: "Home"
        case .conversations: "Conversations"
        case .you: "You"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
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
