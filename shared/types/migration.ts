import type { CareerProfile, TrajectorySnapshot } from './career';
import type { Goal, PerformanceReview } from './goals';
import type { ActionItem, EntryAnalysis, JournalEntry } from './journal';

export interface LegacyExportBundleV1 {
  schemaVersion: 1;
  exportedAt: string;
  userId: string;
  profile: CareerProfile;
  entries: JournalEntry[];
  analyses: EntryAnalysis[];
  sessions: Array<{
    id: string;
    entryId: string | null;
    title: string | null;
    startedAt: string;
    status: 'active' | 'ended';
  }>;
  messages: Array<{
    id: string;
    sessionId: string;
    role: 'user' | 'assistant';
    content: string;
    createdAt: string;
  }>;
  goals: Goal[];
  actions: ActionItem[];
  reviews: PerformanceReview[];
  trajectory: TrajectorySnapshot[];
}
