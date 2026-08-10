import {
  COACHING_GATEWAY_LIMITS,
  firstCoachingRequestContractViolation,
  type CoachingRequest,
} from '@taisa/shared';

import { CoachingRequestSchema } from '../schemas/coaching';

const NOW = '2026-08-10T09:00:00.000Z';

function requestAtPortableLimits(): CoachingRequest {
  const ids = Array.from(
    { length: COACHING_GATEWAY_LIMITS.maxIdListLength },
    (_, index) => `id-${String(index).padStart(2, '0')}`,
  );
  return {
    requestId: '11111111-1111-4111-8111-111111111111',
    submittedAt: NOW,
    input: 'i'.repeat(COACHING_GATEWAY_LIMITS.maxTextLength),
    context: {
      profile: {
        currentRole: 'r'.repeat(COACHING_GATEWAY_LIMITS.maxProfileFieldLength),
        currentCompany: 'c'.repeat(COACHING_GATEWAY_LIMITS.maxProfileFieldLength),
        careerStage: 'senior',
        coachingStyle: 'supportive',
        accountabilityLevel: 'moderate',
      },
      recentMessages: Array.from(
        { length: COACHING_GATEWAY_LIMITS.maxRecentMessages },
        () => ({ role: 'user' as const, content: 'm'.repeat(COACHING_GATEWAY_LIMITS.maxTextLength) }),
      ),
      memory: [
        {
          id: 'm'.repeat(COACHING_GATEWAY_LIMITS.maxIdLength),
          type: 'goal',
          statement: 's'.repeat(COACHING_GATEWAY_LIMITS.maxTextLength),
          provenance: 'user-confirmed',
          lifecycle: 'active',
          confidence: 'established',
          createdAt: NOW,
          confirmedAt: NOW,
          lastSupportedAt: NOW,
          statusChangedAt: NOW,
          sourceMessageIds: ids,
          supersedesId: null,
        },
      ],
      evidence: [
        {
          id: 'evidence-at-limit',
          statement: 'e'.repeat(COACHING_GATEWAY_LIMITS.maxTextLength),
          occurredAt: NOW,
          sourceMessageIds: ids,
          goalIds: ids,
          actionIds: ids,
        },
      ],
    },
  };
}

test('the backend runtime schema accepts the shared portable boundary fixture', () => {
  const request = requestAtPortableLimits();
  expect(firstCoachingRequestContractViolation(request)).toBeNull();
  expect(CoachingRequestSchema.safeParse(request).success).toBe(true);
});

test.each([
  [
    'input text',
    (request: CoachingRequest) => {
      request.input += 'x';
    },
  ],
  [
    'profile identity',
    (request: CoachingRequest) => {
      request.context.profile!.currentRole += 'x';
    },
  ],
  [
    'message count',
    (request: CoachingRequest) => {
      request.context.recentMessages.push({ role: 'user', content: 'extra' });
    },
  ],
  [
    'memory count',
    (request: CoachingRequest) => {
      request.context.memory = Array.from(
        { length: COACHING_GATEWAY_LIMITS.maxMemoryItems + 1 },
        (_, index) => ({ ...request.context.memory[0], id: `memory-${index}` }),
      );
    },
  ],
  [
    'evidence count',
    (request: CoachingRequest) => {
      request.context.evidence = Array.from(
        { length: COACHING_GATEWAY_LIMITS.maxEvidenceItems + 1 },
        (_, index) => ({ ...request.context.evidence[0], id: `evidence-${index}` }),
      );
    },
  ],
  [
    'relationship count',
    (request: CoachingRequest) => {
      request.context.memory[0].sourceMessageIds.push('one-too-many');
    },
  ],
])('the backend runtime schema rejects values beyond the shared %s limit', (_name, mutate) => {
  const request = requestAtPortableLimits();
  mutate(request);
  expect(firstCoachingRequestContractViolation(request)).not.toBeNull();
  expect(CoachingRequestSchema.safeParse(request).success).toBe(false);
});
