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

export type CoachingResponseMode = 'coach' | 'clarify' | 'redirect';
export type CoachingRelevance = 'career-relevant' | 'adjacent' | 'outside-scope';
export type ContextSufficiency = 'sufficient' | 'partial' | 'insufficient';
export type CoachingStance = 'mirror' | 'nudge' | 'challenge' | 'direct';

export type CoachingResponseDecision =
  | {
    mode: 'coach';
    relevance: Exclude<CoachingRelevance, 'outside-scope'>;
    contextSufficiency: Exclude<ContextSufficiency, 'insufficient'>;
    stance: CoachingStance;
    proposals: Array<MemoryDelta | OutcomeDelta>;
  }
  | {
    mode: 'clarify';
    relevance: CoachingRelevance;
    contextSufficiency: 'insufficient';
    stance: null;
    proposals: [];
  }
  | {
    mode: 'redirect';
    relevance: 'outside-scope';
    contextSufficiency: Exclude<ContextSufficiency, 'insufficient'>;
    stance: null;
    proposals: [];
  };

export type CoachingResponse = CoachingResponseDecision & {
  requestId: string;
  reply: string;
  usage: UsageReceipt;
};
