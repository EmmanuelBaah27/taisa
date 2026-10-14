public struct HomeLimits: Sendable, Equatable {
    public let conversations: Int
    public let goals: Int
    public let actions: Int

    public init(conversations: Int, goals: Int, actions: Int) {
        self.conversations = conversations
        self.goals = goals
        self.actions = actions
    }

    public static let `default` = HomeLimits(conversations: 5, goals: 5, actions: 5)
}

public struct HomeSnapshot: Sendable, Equatable {
    public let conversations: [ConversationRecord]
    public let goals: [GoalRecord]
    public let actions: [ActionRecord]
    public let thisWeek: [WeeklyWorkItem]
    public let unresolvedPriorWeekCount: Int
    public let leadInsight: InsightRecord?
    public let hasConfirmedInsightHistory: Bool

    public init(
        conversations: [ConversationRecord],
        goals: [GoalRecord],
        actions: [ActionRecord],
        thisWeek: [WeeklyWorkItem] = [],
        unresolvedPriorWeekCount: Int = 0,
        leadInsight: InsightRecord? = nil,
        hasConfirmedInsightHistory: Bool = false
    ) {
        self.conversations = conversations
        self.goals = goals
        self.actions = actions
        self.thisWeek = thisWeek
        self.unresolvedPriorWeekCount = unresolvedPriorWeekCount
        self.leadInsight = leadInsight
        self.hasConfirmedInsightHistory = hasConfirmedInsightHistory
    }

    public var isEmpty: Bool {
        conversations.isEmpty && goals.isEmpty && actions.isEmpty && thisWeek.isEmpty &&
            unresolvedPriorWeekCount == 0 && leadInsight == nil && !hasConfirmedInsightHistory
    }
}

public enum HomeQueryError: Error, Sendable, Equatable {
    case invalidLimit
    case readFailed
}
