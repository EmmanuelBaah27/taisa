import type {
  LocalCareerProfile,
  LocalEvidenceItem,
  LocalMemoryItem,
  LocalMessage,
} from '@taisa/shared';

import {
  assembleCoachingContext,
  ContextBudgetExceededError,
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
  requestId: 'request-context-1',
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
    const serialized = JSON.stringify({
      requestId: baseInput.requestId,
      submittedAt: baseInput.submittedAt,
      input: baseInput.submittedThought,
      context: result.context,
    });

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
});
