import type { CareerProfile } from './career';
import type { EvidenceItem, MemoryDelta, MemoryItem } from './memory';

export type OutcomeDelta = {
  operation: 'propose-outcome';
  candidate:
    | { kind: 'goal'; title: string; description: string | null; priority: 'low' | 'medium' | 'high' | null; targetDate: string | null; supersedesId: string | null }
    | { kind: 'action'; title: string; description: string | null; priority: 'low' | 'medium' | 'high' | null; dueAt: string | null; goalId: string | null; supersedesId: string | null }
    | { kind: 'evidence'; statement: string; occurredAt: string; goalIds: string[]; actionIds: string[] };
  reason: string;
  requiresConfirmation: true;
};

export interface CoachingContext {
  profile: Pick<
    CareerProfile,
    'currentRole' | 'currentCompany' | 'careerStage' | 'coachingStyle' | 'accountabilityLevel' |
    'currentFocusArea' | 'shortTermGoal' | 'longTermGoal'
  > | null;
  recentMessages: Array<{ role: 'user' | 'assistant'; content: string }>;
  memory: MemoryItem[];
  evidence: EvidenceItem[];
}

export interface CoachingRequest {
  requestId: string;
  submittedAt: string;
  input: string;
  context: CoachingContext;
}

export interface UsageReceipt {
  provider: 'anthropic' | 'openai';
  model: string;
  inputTokens?: number;
  outputTokens?: number;
  audioSeconds?: number;
  estimatedCostUsd: number;
}

export interface CoachingResponse {
  requestId: string;
  reply: string;
  stance: 'mirror' | 'nudge' | 'challenge' | 'direct';
  proposals: Array<MemoryDelta | OutcomeDelta>;
  usage: UsageReceipt;
}
