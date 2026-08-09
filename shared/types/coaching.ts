import type { CareerProfile } from './career';
import type { EvidenceItem, MemoryDelta, MemoryItem } from './memory';

export interface CoachingContext {
  profile: Pick<
    CareerProfile,
    'currentRole' | 'currentCompany' | 'careerStage' | 'coachingStyle' | 'accountabilityLevel'
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
  proposals: MemoryDelta[];
  usage: UsageReceipt;
}
