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

enum WorkDestination: Hashable, Sendable, Identifiable {
    case tasks(route: CareerWorkRoute?)
    case goals(route: CareerWorkRoute?)

    var id: String {
        switch self {
        case let .tasks(route): "tasks:\(route?.stableID ?? "root")"
        case let .goals(route): "goals:\(route?.stableID ?? "root")"
        }
    }

    static func restoringLegacyCareerWork(routeStableID: String?) -> WorkDestination {
        guard let route = CareerWorkRoute(stableID: routeStableID) else { return .tasks(route: nil) }
        return switch route {
        case .action: .tasks(route: route)
        case .goal, .evidence: .goals(route: route)
        case .overview: .tasks(route: nil)
        }
    }
}

private extension CareerWorkRoute {
    var stableID: String {
        switch self {
        case .overview: "overview"
        case let .action(id): "action:\(id)"
        case let .goal(id): "goal:\(id)"
        case let .evidence(id): "evidence:\(id)"
        }
    }

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
