import type { CoachingResponse } from './coaching';
import { firstCoachingResponseContractViolation } from '../coachingLimits';

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

function isCoachingResponse(value: unknown, requestId: string): value is CoachingResponse {
  return firstCoachingResponseContractViolation(value, requestId) === null;
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
