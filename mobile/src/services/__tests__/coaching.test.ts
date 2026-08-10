import type { CoachingRequest, CoachingResponse } from '@taisa/shared';

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
