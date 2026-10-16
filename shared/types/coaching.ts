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
  preferenceProfile?: CoachingPreferenceProfileContext;
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

export const RESPONSE_QUALITY_FACTORS = [
  'evidence_fidelity', 'intent_alignment', 'coverage', 'coaching_strategy',
  'insight_value', 'practical_utility', 'confidence_calibration',
  'relational_fit', 'communication_clarity',
] as const;

export type ResponseQualityFactor = typeof RESPONSE_QUALITY_FACTORS[number];
export type ResponseFeedbackDirection = 'helpful' | 'not_helpful';
export interface ResponseFeedbackSelection {
  direction: ResponseFeedbackDirection;
  factors: ResponseQualityFactor[];
  detail?: string;
}
export interface CoachingPreferenceSignal {
  factor: Exclude<ResponseQualityFactor, 'evidence_fidelity'>;
  direction: ResponseFeedbackDirection;
}
export interface CoachingPreferenceProfileContext { signals: CoachingPreferenceSignal[] }

export type ResponseSourceType = 'message' | 'goal' | 'action' | 'evidence' | 'memory' | 'insight';
export interface ResponseExplanation {
  mode: CoachingStance | null;
  evidence: Array<{ sourceId: string; sourceType: ResponseSourceType; excerpt: string | null }>;
  inference: string;
  confidence: 'low' | 'medium' | 'high';
  approach: string;
}

export type CoachingProposal =
  | { kind: 'goal'; title: string; description: string | null; priority: 'low' | 'medium' | 'high' | null; targetDate: string | null }
  | { kind: 'action'; title: string; description: string | null; priority: 'low' | 'medium' | 'high' | null; dueAt: string | null; goalId: string | null }
  | { kind: 'weekly_work'; actionId: string; weekStart: string; plannedDay: string | null }
  | { kind: 'evidence'; statement: string; occurredAt: string; goalId: string | null; actionId: string | null }
  | { kind: 'memory'; memory: MemoryDelta }
  | { kind: 'insight'; body: string; isTimeSensitive: boolean; homeEligibleUntil: string | null };

export type CoachingResponseDecision =
  | {
    mode: 'coach';
    relevance: Exclude<CoachingRelevance, 'outside-scope'>;
    contextSufficiency: Exclude<ContextSufficiency, 'insufficient'>;
    stance: CoachingStance;
    explanation: ResponseExplanation & { mode: CoachingStance };
    proposal: CoachingProposal | null;
  }
  | {
    mode: 'clarify';
    relevance: CoachingRelevance;
    contextSufficiency: 'insufficient';
    stance: null;
    explanation: ResponseExplanation & { mode: null };
    proposal: null;
  }
  | {
    mode: 'redirect';
    relevance: 'outside-scope';
    contextSufficiency: Exclude<ContextSufficiency, 'insufficient'>;
    stance: null;
    explanation: ResponseExplanation & { mode: null };
    proposal: null;
  };

export type CoachingResponse = CoachingResponseDecision & {
  requestId: string;
  reply: string;
  usage: UsageReceipt;
  titleSuggestion?: string;
};
