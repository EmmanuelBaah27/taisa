import type { CoachingRequest, CoachingResponse, MemoryDelta, UsageReceipt } from '@taisa/shared';

import api from './api';

interface HttpClient {
  post(path: string, body: unknown, config?: unknown): Promise<{ data: unknown }>;
}

export class CoachingClientError extends Error {
  constructor(readonly code: 'COACHING_REQUEST_FAILED' | 'INVALID_COACHING_RESPONSE') {
    super(code === 'INVALID_COACHING_RESPONSE'
      ? 'Taisa received an invalid coaching response.'
      : 'Taisa could not complete the coaching request.');
    this.name = 'CoachingClientError';
  }
}

function object(value: unknown): Record<string, unknown> | null {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function nonNegativeNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0;
}

function validUsage(value: unknown): value is UsageReceipt {
  const item = object(value);
  return item !== null &&
    (item.provider === 'openai' || item.provider === 'anthropic') &&
    typeof item.model === 'string' && item.model.length > 0 &&
    (item.inputTokens === undefined || nonNegativeNumber(item.inputTokens)) &&
    (item.outputTokens === undefined || nonNegativeNumber(item.outputTokens)) &&
    (item.audioSeconds === undefined || nonNegativeNumber(item.audioSeconds)) &&
    nonNegativeNumber(item.estimatedCostUsd);
}

function validMemoryDelta(value: unknown): value is MemoryDelta {
  const item = object(value);
  if (item === null || typeof item.reason !== 'string' || item.reason.trim().length === 0) {
    return false;
  }
  if (item.operation === 'support') {
    return typeof item.targetId === 'string' && item.targetId.length > 0 &&
      typeof item.sourceMessageId === 'string' && item.sourceMessageId.length > 0 &&
      item.requiresConfirmation === false;
  }
  if (item.operation === 'transition') {
    return typeof item.targetId === 'string' && item.targetId.length > 0 &&
      ['proposed', 'active', 'paused', 'superseded', 'completed', 'rejected', 'archived']
        .includes(String(item.to)) &&
      typeof item.requiresConfirmation === 'boolean';
  }
  if (item.operation !== 'propose' || typeof item.requiresConfirmation !== 'boolean') return false;
  const candidate = object(item.candidate);
  return candidate !== null &&
    ['goal', 'commitment', 'decision', 'preference', 'career_context', 'development_area', 'evidence', 'pattern']
      .includes(String(candidate.type)) &&
    typeof candidate.statement === 'string' && candidate.statement.trim().length > 0 &&
    ['user-stated', 'user-confirmed', 'ai-inferred', 'system-observed']
      .includes(String(candidate.provenance)) &&
    ['proposed', 'active', 'paused', 'superseded', 'completed', 'rejected', 'archived']
      .includes(String(candidate.lifecycle)) &&
    ['tentative', 'supported', 'established'].includes(String(candidate.confidence)) &&
    Array.isArray(candidate.sourceMessageIds) &&
    candidate.sourceMessageIds.every((id) => typeof id === 'string');
}

function validatedResponse(value: unknown, requestId: string): CoachingResponse | null {
  const envelope = object(value);
  const data = envelope?.success === true ? object(envelope.data) : null;
  if (
    data === null || data.requestId !== requestId ||
    typeof data.reply !== 'string' || data.reply.trim().length === 0 || data.reply.length > 4_000 ||
    !['mirror', 'nudge', 'challenge', 'direct'].includes(String(data.stance)) ||
    !Array.isArray(data.proposals) || !data.proposals.every(validMemoryDelta) ||
    !validUsage(data.usage)
  ) return null;
  return data as unknown as CoachingResponse;
}

export function createCoachingClient(http: HttpClient) {
  return async function requestCoaching(request: CoachingRequest): Promise<CoachingResponse> {
    try {
      const response = await http.post('/coaching/respond', request, {
        headers: { 'x-request-id': request.requestId },
      });
      const validated = validatedResponse(response.data, request.requestId);
      if (validated === null) throw new CoachingClientError('INVALID_COACHING_RESPONSE');
      return validated;
    } catch (error) {
      if (error instanceof CoachingClientError) throw error;
      throw new CoachingClientError('COACHING_REQUEST_FAILED');
    }
  };
}

export const requestCoaching = createCoachingClient(api);
