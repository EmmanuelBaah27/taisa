import type {
  AccountabilityLevel,
  CareerStage,
  CoachingStyle,
} from './career';
import type {
  EvidenceItem,
  MemoryItem,
} from './memory';

export interface LocalCareerProfile {
  id: string;
  currentRole: string | null;
  currentCompany: string | null;
  industry: string | null;
  yearsOfExperience: number | null;
  careerStage: CareerStage | null;
  currentFocusArea: string | null;
  shortTermGoal: string | null;
  longTermGoal: string | null;
  coachingStyle: CoachingStyle | null;
  accountabilityLevel: AccountabilityLevel | null;
  reminderTimes: string[];
  createdAt: string;
  updatedAt: string;
}

export type ConversationLifecycle = 'active' | 'archived';

export interface LocalConversation {
  id: string;
  title: string | null;
  lifecycle: ConversationLifecycle;
  createdAt: string;
  updatedAt: string;
  archivedAt: string | null;
}

export type MessageRole = 'user' | 'assistant';
export type MessageLifecycle = 'private' | 'pending' | 'submitted' | 'received' | 'failed';

export interface LocalMessage {
  id: string;
  conversationId: string;
  parentMessageId: string | null;
  role: MessageRole;
  content: string;
  lifecycle: MessageLifecycle;
  requestId: string | null;
  createdAt: string;
  updatedAt: string;
}

export type LocalGoalLifecycle =
  | 'proposed'
  | 'active'
  | 'paused'
  | 'superseded'
  | 'completed'
  | 'rejected'
  | 'archived';
export type LocalPriority = 'low' | 'medium' | 'high';

export interface LocalGoal {
  id: string;
  title: string;
  description: string | null;
  lifecycle: LocalGoalLifecycle;
  priority: LocalPriority | null;
  progressPercent: number;
  targetDate: string | null;
  sourceMessageId: string | null;
  supersedesId: string | null;
  createdAt: string;
  updatedAt: string;
  statusChangedAt: string;
}

export type LocalMilestoneLifecycle = 'pending' | 'completed' | 'archived';

export interface LocalMilestone {
  id: string;
  goalId: string;
  title: string;
  lifecycle: LocalMilestoneLifecycle;
  createdAt: string;
  updatedAt: string;
  completedAt: string | null;
}

export type LocalActionLifecycle = 'proposed' | 'open' | 'completed' | 'dropped' | 'archived';

export interface LocalAction {
  id: string;
  goalId: string | null;
  sourceMessageId: string | null;
  title: string;
  description: string | null;
  lifecycle: LocalActionLifecycle;
  priority: LocalPriority | null;
  dueAt: string | null;
  supersedesId: string | null;
  createdAt: string;
  updatedAt: string;
  statusChangedAt: string;
}

export interface LocalEvidenceItem extends EvidenceItem {
  createdAt: string;
  updatedAt: string;
}

export interface LocalMemoryItem extends MemoryItem {
  sourceEvidenceIds: string[];
  updatedAt: string;
}

export interface LocalMemorySource {
  id: string;
  memoryItemId: string;
  messageId: string | null;
  evidenceId: string | null;
  linkedAt: string;
}
