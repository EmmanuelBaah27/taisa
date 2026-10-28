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
    case active, completed, dropped

    /// Compatibility spelling for pre-v8 callers. New persistence always writes `active`.
    public static let open: Self = .active

    public func canTransition(to next: Self) -> Bool {
        switch (self, next) {
        case (.active, .completed), (.active, .dropped), (.completed, .active), (.dropped, .active): true
        default: false
        }
    }
}

public struct ActionDueDay: RawRepresentable, Codable, Sendable, Equatable, Hashable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard let value = try? Self(validating: rawValue) else { return nil }
        self = value
    }

    public init(validating candidate: String) throws {
        let characters = Array(candidate)
        guard characters.count == 10,
              characters[4] == "-", characters[7] == "-",
              characters.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || $0.element.isNumber }),
              let year = Int(candidate.prefix(4)),
              let month = Int(candidate.dropFirst(5).prefix(2)),
              let day = Int(candidate.suffix(2)) else {
            throw CareerWorkContractError.invalidDueDay
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date).year == year,
              calendar.dateComponents([.year, .month, .day], from: date).month == month,
              calendar.dateComponents([.year, .month, .day], from: date).day == day else {
            throw CareerWorkContractError.invalidDueDay
        }
        rawValue = candidate
    }

    public init(from decoder: Decoder) throws {
        try self.init(validating: decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        try value.encode(rawValue)
    }
}

public enum ActionOrigin: String, Codable, Sendable, CaseIterable { case manual }
public enum ActionChecklistState: String, Codable, Sendable, CaseIterable { case pending, completed, promoted }
public enum ActionEventKind: String, Codable, Sendable, CaseIterable {
    case created, edited
    case relationshipChanged = "relationship_changed"
    case checklistChanged = "checklist_changed"
    case checklistPromoted = "checklist_promoted"
    case completed, dropped, reopened
    case completionCorrected = "completion_corrected"
    case deleted, restored
}
public enum ActionParentContext: Sendable, Equatable {
    case standalone
    case goal(id: String)
    case milestone(goalID: String, milestoneID: String)
}
public enum ActionLifecycleFilter: String, Codable, Sendable, CaseIterable { case active, completed, dropped }
public enum ActionDueFilter: String, Codable, Sendable, CaseIterable { case all, overdue, due, noDueDay }
public enum ActionDuplicateDecision: String, Codable, Sendable, CaseIterable { case openExisting, createSeparate }

public enum EvidenceOrigin: String, Codable, Sendable, CaseIterable {
    case user, action, conversation, `import`
}

public enum ProposalDecision: String, Codable, Sendable, CaseIterable {
    case accepted, corrected, rejected, undone
}

public enum CareerWorkMutationSource: String, Codable, Sendable, CaseIterable {
    case user, proposal, undo, migration
}

public enum CareerWorkContractError: Error, Equatable, Sendable {
    case invalidTitle
    case invalidDueDay
    case invalidTransition
    case invalidRelationship
    case staleTarget

    public var diagnosticCode: String {
        switch self {
        case .invalidTitle: "career_work_invalid_title"
        case .invalidDueDay: "career_work_invalid_due_day"
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
