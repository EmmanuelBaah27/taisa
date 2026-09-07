export type WorkRecordKind = 'task' | 'followup' | 'blocker' | 'decision';
export type WorkFreshness = 'current' | 'needs_confirmation' | 'stale';
export type TaskStatus = 'open' | 'completed' | 'removed';
export type FollowupStatus = 'waiting' | 'completed' | 'rescheduled' | 'cancelled';
export type BlockerStatus = 'active' | 'being_resolved' | 'resolved' | 'no_longer_relevant';
export type DecisionStatus = 'current' | 'reopened' | 'superseded' | 'reversed';
export type WorkStatus = TaskStatus | FollowupStatus | BlockerStatus | DecisionStatus;

export interface Project {
  id: string;
  name: string;
  status: 'active' | 'archived';
  sourceId: string;
  revision: number;
  createdAt: string;
  updatedAt: string;
}

interface WorkRecordBase {
  id: string;
  title: string;
  projectId: string | null;
  status: WorkStatus;
  freshness: WorkFreshness;
  plannedWeek: string | null;
  plannedDay: string | null;
  sourceId: string;
  revision: number;
  createdAt: string;
  updatedAt: string;
  lastConfirmedAt: string | null;
}

export type WorkRecord =
  | (WorkRecordBase & { kind: 'task'; status: TaskStatus })
  | (WorkRecordBase & { kind: 'followup'; status: FollowupStatus })
  | (WorkRecordBase & { kind: 'blocker'; status: BlockerStatus })
  | (WorkRecordBase & { kind: 'decision'; status: DecisionStatus });

export interface WorkRelationship {
  id: string;
  recordId: string;
  conversationId: string;
  role: 'primary' | 'supporting';
  contribution: 'planning' | 'status' | 'blocker' | 'decision' | 'outcome' | 'evidence';
  sourceRevision: number;
  createdAt: string;
}

export interface WeeklyPeriod {
  id: string;
  startsOn: string;
  endsOn: string;
  state: 'open' | 'auto_closed_unreviewed' | 'reviewed';
  reviewedAt: string | null;
  closedAt: string | null;
}

export interface WeeklyPeriodSnapshot {
  id: string;
  periodId: string;
  recordIds: string[];
  createdAt: string;
}
