import { COACHING_GATEWAY_LIMITS, type CoachingRequest, type CoachingResponse } from '@taisa/shared';

import { CoachingClientError, createCoachingClient } from '../coaching';

const request: CoachingRequest = {
  requestId: '00000000-0000-4000-8000-000000000001',
  submittedAt: '2026-08-10T09:00:00.000Z',
  input: 'I need perspective.',
  context: { profile: null, recentMessages: [], memory: [], evidence: [] },
};

const response: CoachingResponse = {
  requestId: request.requestId,
  reply: 'What outcome matters most?',
  stance: 'nudge',
  proposals: [],
  usage: {
    provider: 'openai',
    model: 'fixture',
    inputTokens: 10,
    outputTokens: 5,
    estimatedCostUsd: 0.001,
  },
};

test('coaching client sends exactly the portable request and accepts the matching validated response', async () => {
  const post = jest.fn(async () => ({ data: { success: true, data: response } }));
  const client = createCoachingClient({ post });

  await expect(client(request)).resolves.toEqual(response);
  expect(post).toHaveBeenCalledTimes(1);
  expect(post).toHaveBeenCalledWith('/coaching/respond', request, {
    headers: { 'x-request-id': request.requestId },
  });
});

test('coaching client rejects malformed or mismatched output without exposing transport content', async () => {
  const post = jest.fn(async () => ({
    data: {
      success: true,
      data: { ...response, requestId: '00000000-0000-4000-8000-000000000099' },
      privatePayload: 'do not expose this',
    },
  }));
  const client = createCoachingClient({ post });

  let failure: CoachingClientError | null = null;
  try {
    await client(request);
  } catch (error) {
    failure = error as CoachingClientError;
  }

  expect(failure).toBeInstanceOf(CoachingClientError);
  expect(failure?.code).toBe('INVALID_COACHING_RESPONSE');
  expect(failure?.message).not.toContain('do not expose this');
  expect(post).toHaveBeenCalledTimes(1);
});

const propose = {
  operation: 'propose' as const,
  candidate: {
    type: 'goal' as const,
    statement: 'Become a staff designer.',
    provenance: 'ai-inferred' as const,
    lifecycle: 'proposed' as const,
    confidence: 'tentative' as const,
    sourceMessageIds: ['message-1'],
    supersedesId: 'memory-1',
  },
  reason: 'This is a durable direction.',
  requiresConfirmation: true,
};

function coachingEnvelope(data: unknown) {
  return { success: true, data };
}

test.each([
  [
    'unknown response fields',
    { ...response, unexpected: 'private provider detail' },
  ],
  [
    'too many proposals',
    {
      ...response,
      proposals: Array.from(
        { length: COACHING_GATEWAY_LIMITS.maxProposals + 1 },
        () => propose,
      ),
    },
  ],
  [
    'oversized reply text',
    { ...response, reply: 'r'.repeat(COACHING_GATEWAY_LIMITS.maxTextLength + 1) },
  ],
  [
    'unknown proposal fields',
    { ...response, proposals: [{ ...propose, unexpected: true }] },
  ],
  [
    'oversized proposal reasons',
    {
      ...response,
      proposals: [{ ...propose, reason: 'r'.repeat(COACHING_GATEWAY_LIMITS.maxTextLength + 1) }],
    },
  ],
  [
    'oversized candidate text',
    {
      ...response,
      proposals: [{
        ...propose,
        candidate: {
          ...propose.candidate,
          statement: 's'.repeat(COACHING_GATEWAY_LIMITS.maxTextLength + 1),
        },
      }],
    },
  ],
  [
    'oversized target IDs',
    {
      ...response,
      proposals: [{
        operation: 'transition',
        targetId: 'i'.repeat(COACHING_GATEWAY_LIMITS.maxIdLength + 1),
        to: 'paused',
        reason: 'The direction should be paused.',
        requiresConfirmation: true,
      }],
    },
  ],
  [
    'oversized source ID lists',
    {
      ...response,
      proposals: [{
        ...propose,
        candidate: {
          ...propose.candidate,
          sourceMessageIds: Array.from(
            { length: COACHING_GATEWAY_LIMITS.maxIdListLength + 1 },
            (_, index) => `message-${index}`,
          ),
        },
      }],
    },
  ],
  [
    'oversized supersedes IDs',
    {
      ...response,
      proposals: [{
        ...propose,
        candidate: {
          ...propose.candidate,
          supersedesId: 'i'.repeat(COACHING_GATEWAY_LIMITS.maxIdLength + 1),
        },
      }],
    },
  ],
  [
    'unknown usage fields',
    { ...response, usage: { ...response.usage, providerRequestBody: 'private' } },
  ],
  [
    'fractional token counts',
    { ...response, usage: { ...response.usage, inputTokens: 1.5 } },
  ],
  [
    'non-finite cost',
    { ...response, usage: { ...response.usage, estimatedCostUsd: Number.POSITIVE_INFINITY } },
  ],
])('coaching client rejects responses with %s', async (_name, malformedResponse) => {
  const client = createCoachingClient({
    post: jest.fn(async () => ({ data: coachingEnvelope(malformedResponse) })),
  });

  await expect(client(request)).rejects.toMatchObject({
    code: 'INVALID_COACHING_RESPONSE',
  });
});

test('coaching client accepts a strict response at every portable output boundary', async () => {
  const boundaryResponse: CoachingResponse = {
    ...response,
    reply: 'r'.repeat(COACHING_GATEWAY_LIMITS.maxTextLength),
    proposals: Array.from(
      { length: COACHING_GATEWAY_LIMITS.maxProposals },
      () => ({
        ...propose,
        candidate: {
          ...propose.candidate,
          statement: 's'.repeat(COACHING_GATEWAY_LIMITS.maxTextLength),
          sourceMessageIds: Array.from(
            { length: COACHING_GATEWAY_LIMITS.maxIdListLength },
            (_, index) => `message-${index}`,
          ),
          supersedesId: 'i'.repeat(COACHING_GATEWAY_LIMITS.maxIdLength),
        },
        reason: 'r'.repeat(COACHING_GATEWAY_LIMITS.maxTextLength),
      }),
    ),
    usage: {
      provider: 'anthropic',
      model: 'm'.repeat(COACHING_GATEWAY_LIMITS.maxIdLength),
      inputTokens: Number.MAX_SAFE_INTEGER,
      outputTokens: 0,
      audioSeconds: 0.25,
      estimatedCostUsd: 0,
    },
  };
  const client = createCoachingClient({
    post: jest.fn(async () => ({ data: coachingEnvelope(boundaryResponse) })),
  });

  await expect(client(request)).resolves.toEqual(boundaryResponse);
});
