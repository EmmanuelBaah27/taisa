import Foundation

public enum GoalStatus: String, Codable, Sendable, CaseIterable {
    case active, paused, completed

    public func canTransition(to next: Self) -> Bool {
        switch (self, next) {
        case (.active, .paused), (.active, .completed), (.paused, .active), (.completed, .active): true
        default: false
        }
    }
}

public enum MilestoneStatus: String, Codable, Sendable, CaseIterable {
    case planned, completed

    public var storageValue: String { self == .planned ? "open" : rawValue }

    public func canTransition(to next: Self) -> Bool {
        (self == .planned && next == .completed) || (self == .completed && next == .planned)
    }
}

public enum ActionStatus: String, Codable, Sendable, CaseIterable {
    case open, completed

    public func canTransition(to next: Self) -> Bool {
        (self == .open && next == .completed) || (self == .completed && next == .open)
    }
}

public enum EvidenceOrigin: String, Codable, Sendable, CaseIterable {
    case user, action, conversation, `import`
}

public enum ProposalDecision: String, Codable, Sendable, CaseIterable {
    case accepted, corrected, rejected, undone
}

public enum CareerWorkContractError: Error, Equatable, Sendable {
    case invalidTitle
    case invalidTransition
    case invalidRelationship
    case staleTarget

    public var diagnosticCode: String {
        switch self {
        case .invalidTitle: "career_work_invalid_title"
        case .invalidTransition: "career_work_invalid_transition"
        case .invalidRelationship: "career_work_invalid_relationship"
        case .staleTarget: "career_work_stale_target"
        }
    }
}

public struct CareerWorkTitle: Equatable, Sendable {
    public let value: String

    public static func validating(_ candidate: String) throws -> Self {
        let value = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw CareerWorkContractError.invalidTitle }
        return Self(value: value)
    }
}

public enum CareerWorkRoute: Hashable, Sendable {
    case overview
    case goal(id: String)
    case action(id: String)
    case evidence(id: String)

    public var stableID: String {
        switch self {
        case .overview: "overview"
        case let .goal(id): "goal:\(id)"
        case let .action(id): "action:\(id)"
        case let .evidence(id): "evidence:\(id)"
        }
    }
}
