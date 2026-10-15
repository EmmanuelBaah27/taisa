import Foundation
import TaisaDesignSystem

enum PrimaryDestination: String, CaseIterable, Hashable, Sendable {
    case home
    case careerWork
    case conversations
    case you

    static let allCases: [PrimaryDestination] = [.home, .conversations, .you]

    var title: String {
        switch self {
        case .home: "Home"
        case .careerWork: "Career Work"
        case .conversations: "Chats"
        case .you: "You"
        }
    }

    var icon: CentralIconName {
        switch self {
        case .home: .homeLine
        case .careerWork: .homeLine
        case .conversations: .chatBubbles
        case .you: .peopleCircle
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
