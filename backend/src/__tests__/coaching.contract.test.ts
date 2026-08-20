import {
  firstCoachingResponseContractViolation,
  type CoachingRequest,
  type CoachingResponse,
  type MemoryItem,
} from '@taisa/shared';

test('contracts represent a bounded coaching turn and proposed memory change', () => {
  const memory: MemoryItem = {
    id: 'mem-1', type: 'goal', statement: 'Become a Staff Designer',
    provenance: 'user-confirmed', lifecycle: 'active', confidence: 'established',
    createdAt: '2026-08-09T00:00:00Z', confirmedAt: '2026-08-09T00:00:00Z',
    lastSupportedAt: '2026-08-09T00:00:00Z', statusChangedAt: '2026-08-09T00:00:00Z',
    sourceMessageIds: ['m1'],
  };
  const request: CoachingRequest = {
    requestId: '11111111-1111-4111-8111-111111111111', submittedAt: '2026-08-09T00:00:00Z', input: 'I may prefer management',
    context: { profile: null, recentMessages: [], memory: [memory], evidence: [] },
  };
  const response: CoachingResponse = {
    requestId: request.requestId, reply: 'Earlier you preferred the Staff path. Has that changed?',
    mode: 'coach', relevance: 'career-relevant', contextSufficiency: 'sufficient',
    stance: 'challenge', proposals: [],
    usage: { provider: 'anthropic', model: 'test', inputTokens: 10, outputTokens: 8, estimatedCostUsd: 0 },
  };
  expect(response.requestId).toBe(request.requestId);
  expect(firstCoachingResponseContractViolation(response, request.requestId)).toBeNull();
});
