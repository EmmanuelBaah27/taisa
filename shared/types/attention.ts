import type { Insight } from './insights';
import type { WeeklyPeriod, WorkRecord } from './work';

export interface LocalNotification {
  id: string;
  sourceType: 'work_record' | 'proposal' | 'insight' | 'weekly_review' | 'operation';
  sourceId: string;
  groupingKey: string;
  readState: 'unread' | 'read';
  disposition: 'active' | 'snoozed' | 'dismissed';
  snoozedUntil: string | null;
  createdAt: string;
}

export type HomeSectionKind =
  | 'lead_insight'
  | 'this_week'
  | 'carry_over'
  | 'updates_to_review'
  | 'weekly_review'
  | 'organize_week'
  | 'keep_moving'
  | 'conversation_input';

export interface HomeView {
  period: WeeklyPeriod;
  sections: Array<{ kind: HomeSectionKind; itemIds: string[] }>;
  leadInsight: Insight | null;
  thisWeek: WorkRecord[];
  carryOver: WorkRecord[];
  keepMoving: WorkRecord[];
  pendingProposalCount: number;
}
