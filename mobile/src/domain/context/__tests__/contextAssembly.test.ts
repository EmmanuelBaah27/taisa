import type {
  LocalCareerProfile,
  LocalEvidenceItem,
  LocalMemoryItem,
  LocalMessage,
} from '@taisa/shared';
import { COACHING_GATEWAY_LIMITS } from '@taisa/shared';

import {
  assembleCoachingContext,
  ContextBudgetExceededError,
  ContextContractViolationError,
  type ContextRepositories,
} from '../assembleContext';
import { rankEvidence } from '../rankEvidence';

const NOW = '2026-08-10T09:00:00.000Z';

function memory(id: string, statement = `Durable direction ${id}`): LocalMemoryItem {
  return {
    id,
    type: 'career_context',
    statement,
    provenance: 'user-confirmed',
    lifecycle: 'active',
    confidence: 'established',
    createdAt: NOW,
    confirmedAt: NOW,
    lastSupportedAt: NOW,
    statusChangedAt: NOW,
    updatedAt: NOW,
    sourceMessageIds: [`source-${id}`],
    sourceEvidenceIds: [],
    supersedesId: null,
  };
}

function evidence(
  id: string,
  statement: string,
  occurredAt: string,
  links: Partial<Pick<LocalEvidenceItem, 'sourceMessageIds' | 'goalIds' | 'actionIds'>> = {},
): LocalEvidenceItem {
  return {
    id,
    statement,
    occurredAt,
    sourceMessageIds: links.sourceMessageIds ?? [],
    goalIds: links.goalIds ?? [],
    actionIds: links.actionIds ?? [],
    createdAt: occurredAt,
    updatedAt: occurredAt,
  };
}

const profile: LocalCareerProfile = {
  id: 'profile-device',
  currentRole: 'Product Designer',
  currentCompany: 'Example Co',
  industry: 'Technology',
  yearsOfExperience: 8,
  careerStage: 'senior',
  currentFocusArea: 'Influence',
  shortTermGoal: 'Lead strategy work',
  longTermGoal: 'Become Staff',
  coachingStyle: 'supportive',
  accountabilityLevel: 'moderate',
  reminderTimes: [],
  createdAt: NOW,
  updatedAt: NOW,
};

const baseInput = {
  requestId: '11111111-1111-4111-8111-111111111111',
  submittedAt: NOW,
  submittedThought: 'I led the café launch 🚀',
  conversationId: 'conversation-1',
  profileId: profile.id,
  directEvidenceIds: [] as string[],
  directSourceMessageIds: [] as string[],
  relatedGoalIds: [] as string[],
  relatedActionIds: [] as string[],
};

describe('rankEvidence', () => {
  test('uses explicit links, shared entities, recency, normalized relevance, then stable IDs', () => {
    const candidates = [
      evidence('text-z', 'STAFF leadership', '2026-05-01T00:00:00.000Z'),
      evidence('text-a', 'staff, leadership!', '2026-05-01T00:00:00.000Z'),
      evidence('recent', 'Leadership outcome', '2026-08-09T00:00:00.000Z'),
      evidence('shared', 'A separate outcome', '2025-01-01T00:00:00.000Z', {
        goalIds: ['goal-staff'],
      }),
      evidence('direct', 'An old directly linked outcome', '2024-01-01T00:00:00.000Z'),
    ];

    expect(
      rankEvidence(
        {
          text: 'staff leadership',
          directEvidenceIds: ['direct'],
          directSourceMessageIds: [],
          goalIds: ['goal-staff'],
          actionIds: [],
        },
        candidates,
      ).map((item) => item.id),
    ).toEqual(['direct', 'shared', 'recent', 'text-a', 'text-z']);
  });

  test('matches normalized tokens without treating substrings as the same word', () => {
    const ranked = rankEvidence(
      {
        text: 'café staff',
        directEvidenceIds: [],
        directSourceMessageIds: [],
        goalIds: [],
        actionIds: [],
      },
      [
        evidence('substring', 'Staffing plan', NOW),
        evidence('normalized', 'CAFE outcome', NOW),
      ],
    );

    expect(ranked.map((item) => item.id)).toEqual(['normalized']);
  });
});

describe('assembleCoachingContext', () => {
  test('enforces hard item caps and records included and excluded IDs', async () => {
    const messages: LocalMessage[] = Array.from({ length: 25 }, (_, index) => ({
      id: `message-${String(index).padStart(2, '0')}`,
      conversationId: baseInput.conversationId,
      parentMessageId: null,
      role: index % 2 === 0 ? 'user' : 'assistant',
      content: `Message ${index}`,
      lifecycle: index % 2 === 0 ? 'submitted' : 'received',
      requestId: null,
      createdAt: `2026-08-${String(index + 1).padStart(2, '0')}T09:00:00.000Z`,
      updatedAt: `2026-08-${String(index + 1).padStart(2, '0')}T09:00:00.000Z`,
    }));
    const memories = Array.from({ length: 60 }, (_, index) =>
      memory(`memory-${String(index).padStart(2, '0')}`),
    );
    const evidenceItems = Array.from({ length: 12 }, (_, index) =>
      evidence(
        `evidence-${String(index).padStart(2, '0')}`,
        `Launch outcome ${index}`,
        `2026-07-${String(index + 1).padStart(2, '0')}T09:00:00.000Z`,
      ),
    );
    const repositories: ContextRepositories = {
      getProfile: async () => profile,
      listRecentMessages: async () => messages,
      listMemoryCandidates: async () => memories,
      listEvidenceCandidates: async () => evidenceItems,
    };

    const result = await assembleCoachingContext(
      {
        ...baseInput,
        submittedThought: 'What did the launch show?',
        directEvidenceIds: evidenceItems.map((item) => item.id),
      },
      repositories,
      {
        maxCharacters: 100_000,
        maxEstimatedTokens: 100_000,
        memoryCandidateLimit: 80,
        evidenceCandidateLimit: 32,
      },
    );

    expect(result.context.recentMessages).toHaveLength(20);
    expect(result.context.memory).toHaveLength(50);
    expect(result.context.evidence).toHaveLength(8);
    expect(result.manifest.included.messageIds).toEqual(
      messages.slice(5).map((item) => item.id),
    );
    expect(result.manifest.included.memoryIds).toHaveLength(50);
    expect(result.manifest.included.evidenceIds).toHaveLength(8);
    expect(result.manifest.excluded).toEqual(
      expect.arrayContaining([
        { entityType: 'message', id: messages[0].id, reason: 'count-limit' },
        { entityType: 'memory', id: memories[59].id, reason: 'count-limit' },
        { entityType: 'evidence', id: evidenceItems[0].id, reason: 'count-limit' },
      ]),
    );
    expect(result.manifest.queryLimits).toEqual({
      messages: 20,
      memory: 80,
      evidence: 32,
    });
  });

  test('counts the actual serialized request and removes lowest-priority context under budget', async () => {
    const messages: LocalMessage[] = [
      {
        id: 'message-old',
        conversationId: baseInput.conversationId,
        parentMessageId: null,
        role: 'user',
        content: 'Old context '.repeat(20),
        lifecycle: 'submitted',
        requestId: null,
        createdAt: '2026-08-01T09:00:00.000Z',
        updatedAt: '2026-08-01T09:00:00.000Z',
      },
      {
        id: 'message-new',
        conversationId: baseInput.conversationId,
        parentMessageId: 'message-old',
        role: 'assistant',
        content: 'Newest context',
        lifecycle: 'received',
        requestId: null,
        createdAt: NOW,
        updatedAt: NOW,
      },
    ];
    const repositories: ContextRepositories = {
      getProfile: async () => profile,
      listRecentMessages: async () => messages,
      listMemoryCandidates: async () => [memory('memory-budget', 'Long memory '.repeat(20))],
      listEvidenceCandidates: async () => [
        evidence('evidence-budget', 'Long launch evidence '.repeat(20), NOW),
      ],
    };

    const result = await assembleCoachingContext(
      {
        ...baseInput,
        directEvidenceIds: ['evidence-budget'],
      },
      repositories,
      {
        maxCharacters: 750,
        maxEstimatedTokens: 750,
        memoryCandidateLimit: 50,
        evidenceCandidateLimit: 16,
      },
    );
    const serialized = JSON.stringify(result.request);

    expect(result.manifest.serializedCharacters).toBe(serialized.length);
    expect(result.manifest.estimatedTokens).toBeLessThanOrEqual(750);
    expect(result.manifest.estimatedTokens).toBeGreaterThan(serialized.length);
    expect(result.manifest.serializedCharacters).toBeLessThanOrEqual(750);
    expect(result.manifest.excluded).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ reason: expect.stringMatching(/budget$/) }),
      ]),
    );
    expect(result.manifest.included.messageIds).toContain('message-new');
  });

  test('excludes unrelated archive evidence and explains why', async () => {
    const repositories: ContextRepositories = {
      getProfile: async () => null,
      listRecentMessages: async () => [],
      listMemoryCandidates: async () => [],
      listEvidenceCandidates: async () => [
        evidence('evidence-unrelated', 'Quarterly finance reconciliation', NOW),
      ],
    };

    const result = await assembleCoachingContext(
      { ...baseInput, submittedThought: 'How should I handle design leadership?' },
      repositories,
      {
        maxCharacters: 2_000,
        maxEstimatedTokens: 1_000,
        memoryCandidateLimit: 50,
        evidenceCandidateLimit: 16,
      },
    );

    expect(result.context.evidence).toEqual([]);
    expect(result.manifest.excluded).toContainEqual({
      entityType: 'evidence',
      id: 'evidence-unrelated',
      reason: 'not-relevant',
    });
  });

  test('fails closed on a wrong-profile result and explains unsent private messages', async () => {
    const privateMessage: LocalMessage = {
      id: 'message-private',
      conversationId: baseInput.conversationId,
      parentMessageId: null,
      role: 'user',
      content: 'Local draft that was never submitted',
      lifecycle: 'private',
      requestId: null,
      createdAt: NOW,
      updatedAt: NOW,
    };
    const repositories: ContextRepositories = {
      getProfile: async () => ({ ...profile, id: 'profile-other-device' }),
      listRecentMessages: async () => [privateMessage],
      listMemoryCandidates: async () => [],
      listEvidenceCandidates: async () => [],
    };

    const result = await assembleCoachingContext(baseInput, repositories, {
      maxCharacters: 2_000,
      maxEstimatedTokens: 2_000,
      memoryCandidateLimit: 50,
      evidenceCandidateLimit: 16,
    });

    expect(result.context.profile).toBeNull();
    expect(result.context.recentMessages).toEqual([]);
    expect(result.manifest.excluded).toEqual(
      expect.arrayContaining([
        { entityType: 'profile', id: 'profile-other-device', reason: 'scope-mismatch' },
        { entityType: 'message', id: privateMessage.id, reason: 'not-submitted' },
      ]),
    );
  });

  test('fails with content-free diagnostics when the submitted turn alone exceeds the budget', async () => {
    const sensitiveThought = 'Confidential employer detail '.repeat(30);
    const repositories: ContextRepositories = {
      getProfile: async () => null,
      listRecentMessages: async () => [],
      listMemoryCandidates: async () => [],
      listEvidenceCandidates: async () => [],
    };

    let error: unknown;
    try {
      await assembleCoachingContext(
        { ...baseInput, submittedThought: sensitiveThought },
        repositories,
        {
          maxCharacters: 100,
          maxEstimatedTokens: 50,
          memoryCandidateLimit: 50,
          evidenceCandidateLimit: 16,
        },
      );
    } catch (caught) {
      error = caught;
    }

    expect(error).toBeInstanceOf(ContextBudgetExceededError);
    expect(error).toMatchObject({ code: 'CONTEXT_BUDGET_EXCEEDED' });
    expect(String(error)).not.toContain(sensitiveThought.trim());
  });

  test.each([
    ['requestId', { requestId: 'not-a-uuid' }],
    ['submittedAt', { submittedAt: 'not-a-timestamp' }],
    [
      'submittedThought',
      { submittedThought: 'x'.repeat(COACHING_GATEWAY_LIMITS.maxTextLength + 1) },
    ],
  ])('rejects an invalid gateway identity field without exposing content (%s)', async (field, patch) => {
    const repositories: ContextRepositories = {
      getProfile: async () => null,
      listRecentMessages: async () => [],
      listMemoryCandidates: async () => [],
      listEvidenceCandidates: async () => [],
    };

    let error: unknown;
    try {
      await assembleCoachingContext({ ...baseInput, ...patch }, repositories, {
        maxCharacters: 20_000,
        maxEstimatedTokens: 20_000,
        memoryCandidateLimit: 50,
        evidenceCandidateLimit: 16,
      });
    } catch (caught) {
      error = caught;
    }

    expect(error).toBeInstanceOf(ContextContractViolationError);
    expect(error).toMatchObject({ code: 'CONTEXT_CONTRACT_VIOLATION', field });
    expect(String(error)).not.toContain(baseInput.submittedThought);
  });

  test('compacts nested text and relationship lists to portable gateway limits with a content-free manifest', async () => {
    const sourceMessageIds = Array.from(
      { length: COACHING_GATEWAY_LIMITS.maxIdListLength + 5 },
      (_, index) => `source-${String(index).padStart(2, '0')}`,
    ).reverse();
    const goalIds = Array.from(
      { length: COACHING_GATEWAY_LIMITS.maxIdListLength + 3 },
      (_, index) => `goal-${String(index).padStart(2, '0')}`,
    ).reverse();
    const longMessage: LocalMessage = {
      id: 'message-long',
      conversationId: baseInput.conversationId,
      parentMessageId: null,
      role: 'user',
      content: 'm'.repeat(COACHING_GATEWAY_LIMITS.maxTextLength + 7),
      lifecycle: 'submitted',
      requestId: null,
      createdAt: NOW,
      updatedAt: NOW,
    };
    const longMemory = {
      ...memory('memory-long', ` ${'s'.repeat(COACHING_GATEWAY_LIMITS.maxTextLength + 9)} `),
      sourceMessageIds,
    };
    const longEvidence = evidence(
      'evidence-long',
      ` ${'e'.repeat(COACHING_GATEWAY_LIMITS.maxTextLength + 11)} `,
      NOW,
      { sourceMessageIds, goalIds },
    );
    const repositories: ContextRepositories = {
      getProfile: async () => profile,
      listRecentMessages: async () => [longMessage],
      listMemoryCandidates: async () => [longMemory],
      listEvidenceCandidates: async () => [longEvidence],
    };

    const result = await assembleCoachingContext(
      { ...baseInput, directEvidenceIds: [longEvidence.id] },
      repositories,
      {
        maxCharacters: 100_000,
        maxEstimatedTokens: 100_000,
        memoryCandidateLimit: 50,
        evidenceCandidateLimit: 16,
      },
    );

    expect(result.request.context).toEqual(result.context);
    expect(result.request.context.recentMessages[0].content).toHaveLength(
      COACHING_GATEWAY_LIMITS.maxTextLength,
    );
    expect(result.request.context.memory[0].statement).toHaveLength(
      COACHING_GATEWAY_LIMITS.maxTextLength,
    );
    expect(result.request.context.memory[0].sourceMessageIds).toHaveLength(
      COACHING_GATEWAY_LIMITS.maxIdListLength,
    );
    expect(result.request.context.memory[0].sourceMessageIds).toEqual(
      [...sourceMessageIds].sort().slice(0, COACHING_GATEWAY_LIMITS.maxIdListLength),
    );
    expect(result.request.context.evidence[0].goalIds).toHaveLength(
      COACHING_GATEWAY_LIMITS.maxIdListLength,
    );
    expect(result.manifest.excluded).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          entityType: 'message',
          id: longMessage.id,
          field: 'content',
          reason: 'text-truncated',
        }),
        expect.objectContaining({
          entityType: 'memory',
          id: longMemory.id,
          field: 'statement',
          reason: 'text-truncated',
        }),
        expect.objectContaining({
          entityType: 'memory',
          id: longMemory.id,
          field: 'sourceMessageIds',
          relatedId: sourceMessageIds.sort()[COACHING_GATEWAY_LIMITS.maxIdListLength],
          reason: 'relationship-limit',
        }),
        expect.objectContaining({
          entityType: 'evidence',
          id: longEvidence.id,
          field: 'goalIds',
          reason: 'relationship-limit',
        }),
      ]),
    );
    expect(JSON.stringify(result.manifest)).not.toContain('m'.repeat(50));
    expect(JSON.stringify(result.manifest)).not.toContain('s'.repeat(50));
  });

  test('excludes invalid nested identities and timestamps before request serialization', async () => {
    const malformedRelationship = 'not-an-id confidential relationship detail '.repeat(4);
    const invalidMemory = {
      ...memory('memory-invalid-time'),
      lastSupportedAt: 'yesterday',
    };
    const invalidEvidence = evidence('', 'Relevant launch result', NOW, {
      sourceMessageIds: [malformedRelationship],
    });
    const repositories: ContextRepositories = {
      getProfile: async () => profile,
      listRecentMessages: async () => [],
      listMemoryCandidates: async () => [invalidMemory],
      listEvidenceCandidates: async () => [invalidEvidence],
    };

    const result = await assembleCoachingContext(
      { ...baseInput, submittedThought: 'Relevant launch result', directEvidenceIds: [''] },
      repositories,
      {
        maxCharacters: 20_000,
        maxEstimatedTokens: 20_000,
        memoryCandidateLimit: 50,
        evidenceCandidateLimit: 16,
      },
    );

    expect(result.request.context.memory).toEqual([]);
    expect(result.request.context.evidence).toEqual([]);
    expect(result.manifest.excluded).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          entityType: 'memory',
          id: invalidMemory.id,
          field: 'lastSupportedAt',
          reason: 'invalid-field',
        }),
        expect.objectContaining({
          entityType: 'evidence',
          id: invalidEvidence.id,
          field: 'id',
          reason: 'invalid-field',
        }),
      ]),
    );
    expect(JSON.stringify(result.manifest)).not.toContain(malformedRelationship.trim());
  });

  test('never copies a malformed relationship value into the local manifest', async () => {
    const malformedRelationship = 'private relationship-shaped content '.repeat(5);
    const item = memory('memory-invalid-relationship');
    item.sourceMessageIds = [malformedRelationship];
    const repositories: ContextRepositories = {
      getProfile: async () => null,
      listRecentMessages: async () => [],
      listMemoryCandidates: async () => [item],
      listEvidenceCandidates: async () => [],
    };

    const result = await assembleCoachingContext(baseInput, repositories, {
      maxCharacters: 20_000,
      maxEstimatedTokens: 20_000,
      memoryCandidateLimit: 50,
      evidenceCandidateLimit: 16,
    });

    expect(result.context.memory[0].sourceMessageIds).toEqual([]);
    expect(result.manifest.excluded).toContainEqual({
      entityType: 'memory',
      id: item.id,
      field: 'sourceMessageIds',
      reason: 'invalid-field',
    });
    expect(JSON.stringify(result.manifest)).not.toContain(malformedRelationship.trim());
  });

  test('rejects rather than truncating an oversize profile identity field', async () => {
    const repositories: ContextRepositories = {
      getProfile: async () => ({
        ...profile,
        currentRole: 'r'.repeat(COACHING_GATEWAY_LIMITS.maxProfileFieldLength + 1),
      }),
      listRecentMessages: async () => [],
      listMemoryCandidates: async () => [],
      listEvidenceCandidates: async () => [],
    };

    await expect(
      assembleCoachingContext(baseInput, repositories, {
        maxCharacters: 20_000,
        maxEstimatedTokens: 20_000,
        memoryCandidateLimit: 50,
        evidenceCandidateLimit: 16,
      }),
    ).rejects.toMatchObject({
      code: 'CONTEXT_CONTRACT_VIOLATION',
      field: 'profile.currentRole',
    });
  });
});
