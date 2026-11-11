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

    static func restoringLegacyCareerWork(routeStableID: String?) -> WorkDestination {
        guard let route = CareerWorkRoute(stableID: routeStableID) else { return .actions(route: nil) }
        return switch route {
        case .action: .actions(route: route)
        case .goal, .evidence: .goals(route: route)
        case .overview: .actions(route: nil)
        }
    }
}

private extension CareerWorkRoute {
    init?(stableID: String?) {
        guard let stableID else { return nil }
        if stableID == "overview" { self = .overview; return }
        let components = stableID.split(separator: ":", maxSplits: 1).map(String.init)
        guard components.count == 2, !components[1].isEmpty else { return nil }
        switch components[0] {
        case "action": self = .action(id: components[1])
        case "goal", "milestone": self = .goal(id: components[1])
        case "evidence": self = .evidence(id: components[1])
        default: return nil
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
