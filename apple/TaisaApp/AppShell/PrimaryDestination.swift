import Foundation
import TaisaDesignSystem
import TaisaStorage

enum PrimaryDestination: String, CaseIterable, Hashable, Sendable {
    case home
    case conversations
    case you

    static let allCases: [PrimaryDestination] = [.home, .conversations, .you]

    var title: String {
        switch self {
        case .home: "Home"
        case .conversations: "Chats"
        case .you: "You"
        }
    }

    var icon: CentralIconName {
        switch self {
        case .home: .homeLine
        case .conversations: .chatBubbles
        case .you: .peopleCircle
        }
    }
}

enum WorkDestination: Hashable, Sendable {
    case actions(route: CareerWorkRoute?)
    case goals(route: CareerWorkRoute?)
}

enum ConversationEntryIntent: Sendable, Equatable {
    case voice
    case text
}

struct ConversationRoute: Identifiable, Sendable, Equatable {
    let id: String
    let localTitle: String
}
