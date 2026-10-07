import { createHash } from 'node:crypto';
import type {
  CoachingRequest,
  CoachingResponse,
  CoachingStreamEvent,
} from '@taisa/shared';
import { isCoachingStreamEvent } from '@taisa/shared';
import type { CoachingIdempotencyStore } from './coachingIdempotencyStore';

export type PaidCoachingStreamItem =
  | { kind: 'delta'; delta: string }
  | { kind: 'completed'; response: CoachingResponse };

export class AmbiguousPaidWorkError extends Error {
  readonly code = 'AMBIGUOUS_PAID_WORK';
  constructor() { super('Paid coaching work requires reconciliation confirmation'); }
}

export function extractReplyPrefix(partialJSON: string): string {
  const match = /"reply"\s*:\s*"/.exec(partialJSON);
  if (!match) return '';
  let result = '';
  let index = match.index + match[0].length;
  while (index < partialJSON.length) {
    const character = partialJSON[index++];
    if (character === '"') break;
    if (character !== '\\') {
      result += character;
      continue;
    }
    if (index >= partialJSON.length) break;
    const escape = partialJSON[index++];
    const simple: Record<string, string> = {
      '"': '"', '\\': '\\', '/': '/', b: '\b', f: '\f', n: '\n', r: '\r', t: '\t',
    };
    if (escape !== 'u') {
      if (simple[escape] === undefined) break;
      result += simple[escape];
      continue;
    }
    const digits = partialJSON.slice(index, index + 4);
    if (!/^[0-9a-fA-F]{4}$/.test(digits)) break;
    result += String.fromCharCode(Number.parseInt(digits, 16));
    index += 4;
  }
  return result;
}

function canonicalHash(request: CoachingRequest): string {
  return createHash('sha256').update(JSON.stringify(request)).digest('hex');
}

function receiptFor(key: string, requestHash: string): string {
  return createHash('sha256').update(`${key}:${requestHash}`).digest('hex');
}

export async function* executeCoachingStream(input: {
  request: CoachingRequest;
  idempotencyKey: string;
  ownerId: string;
  requestHash?: string;
  store: CoachingIdempotencyStore;
  paidExecution: (
    request: CoachingRequest,
    context: { idempotencyKey: string },
  ) => AsyncIterable<PaidCoachingStreamItem>;
}): AsyncGenerator<CoachingStreamEvent, void, void> {
  const requestHash = input.requestHash ?? canonicalHash(input.request);
  const existing = input.store.begin({
    key: input.idempotencyKey,
    requestId: input.request.requestId,
    requestHash,
    ownerId: input.ownerId,
  });
  if (existing.status === 'ambiguous') throw new AmbiguousPaidWorkError();
  if (existing.status === 'failed') {
    yield {
      type: 'coaching.failed', requestId: input.request.requestId,
      sequence: 0, code: existing.code as any, retryable: existing.retryable,
    };
    return;
  }
  if (existing.status === 'completed') {
    yield {
      type: 'coaching.completed', requestId: input.request.requestId,
      sequence: existing.terminalSequence, response: existing.response,
      idempotencyReceipt: existing.idempotencyReceipt,
    };
    return;
  }

  input.store.markProviderStarted(input.idempotencyKey);
  let sequence = 0;
  let completed = false;
  for await (const item of input.paidExecution(input.request, {
    idempotencyKey: input.idempotencyKey,
  })) {
    if (completed) throw new Error('COACHING_DATA_AFTER_TERMINAL');
    if (item.kind === 'delta') {
      const event: CoachingStreamEvent = {
        type: 'coaching.delta', requestId: input.request.requestId,
        sequence, delta: item.delta,
      };
      if (!isCoachingStreamEvent(event)) throw new Error('INVALID_COACHING_DELTA');
      yield event;
      sequence += 1;
      continue;
    }
    const receipt = receiptFor(input.idempotencyKey, requestHash);
    const event: CoachingStreamEvent = {
      type: 'coaching.completed', requestId: input.request.requestId,
      sequence, response: item.response, idempotencyReceipt: receipt,
    };
    if (!isCoachingStreamEvent(event)) throw new Error('INVALID_COACHING_TERMINAL');
    input.store.complete(input.idempotencyKey, item.response, receipt, event.sequence);
    completed = true;
    yield event;
    sequence += 1;
  }
  if (!completed) throw new Error('COACHING_STREAM_MISSING_TERMINAL');
}
