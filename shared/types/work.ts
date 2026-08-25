export type WorkRecordKind = 'task' | 'followup' | 'blocker' | 'decision' | 'outcome';
export type WorkFreshness = 'current' | 'stale' | 'contradictory';
export type WorkStatus = 'open' | 'in_progress' | 'blocked' | 'completed' | 'cancelled';

export interface Project {
  id: string;
  name: string;
  status: 'active' | 'paused' | 'completed' | 'archived';
  sourceId: string;
  revision: number;
  createdAt: string;
  updatedAt: string;
}

export interface WorkRecord {
  id: string;
  kind: WorkRecordKind;
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
