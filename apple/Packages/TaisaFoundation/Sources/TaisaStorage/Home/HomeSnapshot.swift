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
    public let milestones: [MilestoneRecord]
    public let actions: [ActionRecord]
    public let thisWeek: [WeeklyWorkItem]
    public let unresolvedPriorWeekCount: Int
    public let overdueActions: [ActionRecord]
    public let recentlyReopenedActions: [ActionRecord]
    public let actionReviewFacts: HomeActionReviewFacts
    public let leadInsight: InsightRecord?
    public let hasConfirmedInsightHistory: Bool

    public init(
        conversations: [ConversationRecord],
        goals: [GoalRecord],
        milestones: [MilestoneRecord] = [],
        actions: [ActionRecord],
        thisWeek: [WeeklyWorkItem] = [],
        unresolvedPriorWeekCount: Int = 0,
        overdueActions: [ActionRecord] = [],
        recentlyReopenedActions: [ActionRecord] = [],
        actionReviewFacts: HomeActionReviewFacts = .init(active: 0, completed: 0, dropped: 0, reopened: 0),
        leadInsight: InsightRecord? = nil,
        hasConfirmedInsightHistory: Bool = false
    ) {
        self.conversations = conversations
        self.goals = goals
        self.milestones = milestones
        self.actions = actions
        self.thisWeek = thisWeek
        self.unresolvedPriorWeekCount = unresolvedPriorWeekCount
        self.overdueActions = overdueActions
        self.recentlyReopenedActions = recentlyReopenedActions
        self.actionReviewFacts = actionReviewFacts
        self.leadInsight = leadInsight
        self.hasConfirmedInsightHistory = hasConfirmedInsightHistory
    }

    public var isEmpty: Bool {
        conversations.isEmpty && goals.isEmpty && milestones.isEmpty && actions.isEmpty && thisWeek.isEmpty &&
            overdueActions.isEmpty && recentlyReopenedActions.isEmpty && actionReviewFacts == .init(active: 0, completed: 0, dropped: 0, reopened: 0) &&
            unresolvedPriorWeekCount == 0 && leadInsight == nil && !hasConfirmedInsightHistory
    }
}

public struct HomeActionReviewFacts: Sendable, Equatable {
    public let active: Int
    public let completed: Int
    public let dropped: Int
    public let reopened: Int
    public init(active: Int, completed: Int, dropped: Int, reopened: Int) {
        self.active = active; self.completed = completed; self.dropped = dropped; self.reopened = reopened
    }
}

public enum HomeQueryError: Error, Sendable, Equatable {
    case invalidLimit
    case readFailed
}
