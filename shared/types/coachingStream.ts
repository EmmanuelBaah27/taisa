import type { CoachingResponse, UsageReceipt } from './coaching';

export type CoachingStreamFailureCode =
  | 'COACHING_UNAVAILABLE'
  | 'AUTHENTICATION_FAILED'
  | 'RATE_LIMITED'
  | 'COST_LIMIT_REACHED'
  | 'INVALID_COACHING_OUTPUT'
  | 'INCOMPATIBLE_CONTRACT';

export type CoachingStreamEvent =
  | { type: 'coaching.delta'; requestId: string; sequence: number; delta: string }
  | { type: 'coaching.completed'; requestId: string; sequence: number; response: CoachingResponse; idempotencyReceipt: string }
  | { type: 'coaching.failed'; requestId: string; sequence: number; code: CoachingStreamFailureCode; retryable: boolean };

const REQUEST_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const FAILURE_CODES = new Set<CoachingStreamFailureCode>([
  'COACHING_UNAVAILABLE',
  'AUTHENTICATION_FAILED',
  'RATE_LIMITED',
  'COST_LIMIT_REACHED',
  'INVALID_COACHING_OUTPUT',
  'INCOMPATIBLE_CONTRACT',
]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function hasOnlyKeys(value: Record<string, unknown>, allowed: readonly string[]): boolean {
  const keys = Object.keys(value);
  return keys.length === allowed.length && keys.every((key) => allowed.includes(key));
}

function isFiniteNonNegative(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0;
}

function isUsageReceipt(value: unknown): value is UsageReceipt {
  if (!isRecord(value) || !hasOnlyKeys(value, Object.keys(value).filter((key) => [
    'provider', 'model', 'inputTokens', 'outputTokens', 'audioSeconds', 'estimatedCostUsd',
  ].includes(key)))) return false;
  if (value.provider !== 'anthropic' && value.provider !== 'openai') return false;
  if (typeof value.model !== 'string' || value.model.length === 0) return false;
  if (!isFiniteNonNegative(value.estimatedCostUsd)) return false;
  return ['inputTokens', 'outputTokens', 'audioSeconds'].every((key) =>
    value[key] === undefined || isFiniteNonNegative(value[key]));
}

function isProposal(value: unknown): boolean {
  return isRecord(value) && typeof value.operation === 'string';
}

function isCoachingResponse(value: unknown, requestId: string): value is CoachingResponse {
  if (!isRecord(value) || !hasOnlyKeys(value, [
    'requestId', 'reply', 'mode', 'relevance', 'contextSufficiency', 'stance', 'proposals', 'usage',
  ])) return false;
  if (value.requestId !== requestId || typeof value.reply !== 'string' || value.reply.trim() === '') return false;
  if (!['coach', 'clarify', 'redirect'].includes(String(value.mode))) return false;
  if (!['career-relevant', 'adjacent', 'outside-scope'].includes(String(value.relevance))) return false;
  if (!['sufficient', 'partial', 'insufficient'].includes(String(value.contextSufficiency))) return false;
  if (!(value.stance === null || ['mirror', 'nudge', 'challenge', 'direct'].includes(String(value.stance)))) return false;
  if (!Array.isArray(value.proposals) || !value.proposals.every(isProposal)) return false;
  if (!isUsageReceipt(value.usage)) return false;

  if (value.mode === 'coach') {
    return value.relevance !== 'outside-scope'
      && value.contextSufficiency !== 'insufficient'
      && value.stance !== null;
  }
  if (value.mode === 'clarify') {
    return value.contextSufficiency === 'insufficient'
      && value.stance === null
      && value.proposals.length === 0;
  }
  return value.relevance === 'outside-scope'
    && value.contextSufficiency !== 'insufficient'
    && value.stance === null
    && value.proposals.length === 0;
}

export function isCoachingStreamEvent(value: unknown): value is CoachingStreamEvent {
  if (!isRecord(value)
    || typeof value.requestId !== 'string'
    || !REQUEST_ID_PATTERN.test(value.requestId)
    || !Number.isInteger(value.sequence)
    || (value.sequence as number) < 0) return false;

  switch (value.type) {
    case 'coaching.delta':
      return hasOnlyKeys(value, ['type', 'requestId', 'sequence', 'delta'])
        && typeof value.delta === 'string'
        && value.delta.length > 0;
    case 'coaching.completed':
      return hasOnlyKeys(value, ['type', 'requestId', 'sequence', 'response', 'idempotencyReceipt'])
        && typeof value.idempotencyReceipt === 'string'
        && value.idempotencyReceipt.length > 0
        && isCoachingResponse(value.response, value.requestId);
    case 'coaching.failed':
      return hasOnlyKeys(value, ['type', 'requestId', 'sequence', 'code', 'retryable'])
        && typeof value.code === 'string'
        && FAILURE_CODES.has(value.code as CoachingStreamFailureCode)
        && typeof value.retryable === 'boolean';
    default:
      return false;
  }
}
