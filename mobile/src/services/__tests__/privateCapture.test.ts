import type { CoachingRequest, CoachingResponse } from '@taisa/shared';

import type { RepositoryTransaction } from '../../db/types';
import {
  enqueueAudioCleanup,
  listAudioCleanupQueue,
} from '../../repositories/audioCleanupRepository';
import { listMessages } from '../../repositories/conversationRepository';
import { getMemory, insertMemory, updateMemory } from '../../repositories/memoryRepository';
import { getGoal } from '../../repositories/goalRepository';
import { getAction, insertAction } from '../../repositories/actionRepository';
import { getEvidence, insertEvidence } from '../../repositories/evidenceRepository';
import { insertGoal } from '../../repositories/goalRepository';
import {
  createTestDatabase,
  type TestDatabase,
} from '../../repositories/__tests__/testDatabase';
import {
  createPrivateCaptureService,
  mergeContextMemoryCandidates,
  type AudioFileStore,
  type PrivateCaptureService,
  SubmissionValidationError,
  SubmissionFailedError,
} from '../privateCapture';

const NOW = '2026-08-10T09:00:00.000Z';
const UUIDS = [
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000002',
  '00000000-0000-4000-8000-000000000003',
  '00000000-0000-4000-8000-000000000004',
  '00000000-0000-4000-8000-000000000005',
  '00000000-0000-4000-8000-000000000006',
  '00000000-0000-4000-8000-000000000007',
  '00000000-0000-4000-8000-000000000008',
];

const proposal = {
  operation: 'propose' as const,
  candidate: {
    type: 'goal' as const,
    statement: 'Move toward a Staff IC role',
    provenance: 'user-confirmed' as const,
    lifecycle: 'active' as const,
    confidence: 'established' as const,
    sourceMessageIds: ['provider-supplied-source'],
    supersedesId: null,
  },
  reason: 'This direction may shape future coaching.',
  requiresConfirmation: false,
};

function coachingResponse(request: CoachingRequest): CoachingResponse {
  return {
    requestId: request.requestId,
    reply: 'What would moving toward Staff change in your next project?',
    stance: 'challenge',
    proposals: [proposal],
    usage: {
      provider: 'openai',
      model: 'fixture-model',
      inputTokens: 120,
      outputTokens: 40,
      estimatedCostUsd: 0.003,
    },
  };
}

function conflictingResponse(request: CoachingRequest): CoachingResponse {
  return {
    ...coachingResponse(request),
    proposals: [{
      ...proposal,
      candidate: { ...proposal.candidate, supersedesId: 'old-direction' },
    }],
  };
}

async function seedOldDirection(db: TestDatabase): Promise<void> {
  await db.withTransaction((transaction) => insertMemory(transaction, {
    id: 'old-direction',
    type: 'goal',
    statement: 'Move into design management',
    provenance: 'user-confirmed',
    lifecycle: 'active',
    confidence: 'established',
    supersedesId: null,
    createdAt: NOW,
    confirmedAt: NOW,
    lastSupportedAt: NOW,
    statusChangedAt: NOW,
    updatedAt: NOW,
    sourceMessageIds: [],
    sourceEvidenceIds: [],
  }, 'seed-old-direction'));
}

interface RequestRow {
  id: string;
  user_message_id: string;
  transcription_request_id: string | null;
  status: string;
  audio_uri: string | null;
  transcript_confirmed_at: string | null;
  assistant_message_id: string | null;
  context_manifest_json: string | null;
  error_code: string | null;
  attempt_count: number;
}

async function getRequest(db: TestDatabase, id: string): Promise<RequestRow | null> {
  return db.getFirstAsync<RequestRow>(
    `SELECT id, user_message_id, transcription_request_id, status, audio_uri,
            transcript_confirmed_at, assistant_message_id, context_manifest_json, error_code,
            attempt_count
       FROM coaching_requests WHERE id = $id`,
    { $id: id },
  );
}

describe('private local capture and deliberate submission', () => {
  test('saturated context fairly preserves goals, actions, and durable memory', () => {
    const memory = (id: string, type: 'goal' | 'commitment' | 'decision') => ({
      id, type, statement: id, provenance: 'user-confirmed' as const,
      lifecycle: 'active' as const, confidence: 'established' as const,
      createdAt: NOW, confirmedAt: NOW, lastSupportedAt: NOW, statusChangedAt: NOW,
      sourceMessageIds: [], sourceEvidenceIds: [], updatedAt: NOW, supersedesId: null,
    });
    const selected = mergeContextMemoryCandidates(
      Array.from({ length: 50 }, (_, index) => memory(`goal-${index}`, 'goal')),
      Array.from({ length: 50 }, (_, index) => memory(`action-${index}`, 'commitment')),
      Array.from({ length: 50 }, (_, index) => memory(`memory-${index}`, 'decision')),
      50,
    );
    expect(selected).toHaveLength(50);
    expect(selected.some((item) => item.id.startsWith('goal-'))).toBe(true);
    expect(selected.some((item) => item.id.startsWith('action-'))).toBe(true);
    expect(selected.some((item) => item.id.startsWith('memory-'))).toBe(true);
  });
  let db: TestDatabase;
  let coach: jest.Mock<Promise<CoachingResponse>, [CoachingRequest]>;
  let transcribe: jest.Mock;
  let service: PrivateCaptureService;
  let ids: string[];
  let audioFiles: jest.Mocked<AudioFileStore>;

  beforeEach(() => {
    db = createTestDatabase();
    coach = jest.fn(async (request: CoachingRequest) => coachingResponse(request));
    transcribe = jest.fn(async () => ({
      transcript: 'The roadmap conversation left me uncertain.',
      durationSeconds: 18,
      usage: {
        provider: 'openai' as const,
        model: 'fixture-transcription',
        audioSeconds: 18,
        estimatedCostUsd: 0.0018,
      },
    }));
    ids = [...UUIDS];
    audioFiles = {
      persistRecording: jest.fn(async ({ sourceUri, requestId }) =>
        `file:///documents/taisa-audio/${requestId}-${sourceUri.split('/').at(-1)}`),
      deleteRecording: jest.fn(async (_uri: string) => undefined),
    };
    service = createPrivateCaptureService({
      database: db,
      coach,
      transcribe,
      now: () => NOW,
      createId: () => ids.shift()!,
      getProfileId: async () => 'profile-1',
      audioFiles,
    });
  });

  afterEach(() => db.close());

  test('private save persists a private local message without invoking an external client', async () => {
    const saved = await service.savePrivateDraft({
      conversationId: 'conversation-1',
      content: 'Confidential launch detail',
    });

    expect(saved.status).toBe('private');
    expect((await listMessages(db, 'conversation-1'))).toEqual([
      expect.objectContaining({
        id: saved.messageId,
        content: 'Confidential launch detail',
        lifecycle: 'private',
        requestId: null,
      }),
    ]);
    expect(coach).not.toHaveBeenCalled();
    expect(transcribe).not.toHaveBeenCalled();
    expect(await db.getFirstAsync('SELECT id FROM coaching_requests')).toBeNull();
  });

  test('text submission is pending locally before one bounded gateway call and commits its result atomically', async () => {
    coach.mockImplementationOnce(async (request) => {
      const pending = await getRequest(db, request.requestId);
      const messages = await listMessages(db, 'conversation-1');
      expect(pending?.status).toBe('coaching-pending');
      expect(messages).toEqual([
        expect.objectContaining({
          id: pending?.user_message_id,
          lifecycle: 'pending',
          requestId: request.requestId,
        }),
      ]);
      expect(request.context.recentMessages).toHaveLength(0);
      expect(request.context.memory.length).toBeLessThanOrEqual(50);
      expect(request.context.evidence.length).toBeLessThanOrEqual(8);
      return coachingResponse(request);
    });

    const result = await service.submitText({
      conversationId: 'conversation-1',
      content: 'I may prefer Staff IC work.',
    });

    expect(coach).toHaveBeenCalledTimes(1);
    expect(transcribe).not.toHaveBeenCalled();
    const messages = await listMessages(db, 'conversation-1');
    expect(messages).toHaveLength(2);
    expect(messages[0]).toEqual(expect.objectContaining({
      id: result.messageId,
      lifecycle: 'submitted',
      requestId: result.requestId,
    }));
    expect(messages[1]).toEqual(expect.objectContaining({
      role: 'assistant',
      lifecycle: 'received',
      content: 'What would moving toward Staff change in your next project?',
    }));
    expect(await getRequest(db, result.requestId)).toEqual(expect.objectContaining({
      status: 'completed',
      assistant_message_id: messages[1].id,
      error_code: null,
    }));
    const manifest = JSON.parse((await getRequest(db, result.requestId))!.context_manifest_json!);
    expect(manifest).toEqual(expect.objectContaining({
      included: expect.any(Object),
      queryLimits: { messages: 20, memory: 50, evidence: 32 },
    }));
    expect(JSON.stringify(manifest)).not.toContain('I may prefer Staff IC work.');
    expect(await db.getFirstAsync(
      'SELECT request_id FROM usage_receipts WHERE request_id = $id',
      { $id: result.requestId },
    )).toEqual({ request_id: result.requestId });

    const staged = await db.getFirstAsync<{
      status: string;
      source_message_id: string;
      proposal_json: string;
    }>('SELECT status, source_message_id, proposal_json FROM memory_confirmations');
    expect(staged).toEqual(expect.objectContaining({
      status: 'pending',
      source_message_id: result.messageId,
    }));
    expect(staged?.proposal_json).toContain('"provenance":"ai-inferred"');
    expect(staged?.proposal_json).not.toContain('provider-supplied-source');
  });

  test('deliberate submission includes bounded months-old nonlexical evidence linked to active outcomes', async () => {
    await db.withTransaction(async (transaction) => {
      await insertGoal(transaction, {
        id: 'goal-influence', title: 'Grow stakeholder influence', description: null,
        lifecycle: 'active', priority: 'high', progressPercent: 0, targetDate: null,
        sourceMessageId: null, supersedesId: null, createdAt: NOW, updatedAt: NOW,
        statusChangedAt: NOW,
      }, 'seed-active-goal');
      await insertGoal(transaction, {
        id: 'goal-archived', title: 'Old direction', description: null,
        lifecycle: 'archived', priority: null, progressPercent: 0, targetDate: null,
        sourceMessageId: null, supersedesId: null, createdAt: NOW, updatedAt: NOW,
        statusChangedAt: NOW,
      }, 'seed-archived-goal');
      await insertEvidence(transaction, {
        id: 'evidence-old-related', statement: 'Facilitated alignment across three departments.',
        occurredAt: '2026-01-10T09:00:00.000Z', sourceMessageIds: [],
        goalIds: ['goal-influence'], actionIds: [], createdAt: NOW, updatedAt: NOW,
      }, 'seed-related-evidence');
      await insertEvidence(transaction, {
        id: 'evidence-old-inactive', statement: 'Presented a retired planning framework.',
        occurredAt: '2026-01-09T09:00:00.000Z', sourceMessageIds: [],
        goalIds: ['goal-archived'], actionIds: [], createdAt: NOW, updatedAt: NOW,
      }, 'seed-inactive-evidence');
    });
    coach.mockImplementationOnce(async (request) => {
      return { ...coachingResponse(request), proposals: [] };
    });

    await service.submitText({
      conversationId: 'relationship-context',
      content: 'Navigating power dynamics today.',
    });
    expect(coach).toHaveBeenCalledTimes(1);
    const submittedContext = coach.mock.calls[0]![0].context;
    expect(submittedContext?.memory).toEqual(expect.arrayContaining([
      expect.objectContaining({ id: 'goal-influence', statement: 'Grow stakeholder influence' }),
    ]));
    expect(submittedContext?.evidence).toEqual([
      expect.objectContaining({ id: 'evidence-old-related', goalIds: ['goal-influence'] }),
    ]);
    expect(JSON.stringify(submittedContext)).not.toContain('evidence-old-inactive');
  });

  test('relationship context stays within candidate bounds and is never loaded during private save', async () => {
    await db.withTransaction(async (transaction) => {
      await insertAction(transaction, {
        id: 'action-related', goalId: null, sourceMessageId: null, title: 'Practice influence',
        description: null, lifecycle: 'open', priority: null, dueAt: null, supersedesId: null,
        createdAt: NOW, updatedAt: NOW, statusChangedAt: NOW,
      }, 'seed-related-action');
      for (let index = 0; index < 12; index += 1) {
        await insertEvidence(transaction, {
          id: `evidence-related-${index}`, statement: `Historical unrelated wording ${index}`,
          occurredAt: `2026-01-${String(index + 1).padStart(2, '0')}T09:00:00.000Z`,
          sourceMessageIds: [], goalIds: [], actionIds: ['action-related'],
          createdAt: NOW, updatedAt: NOW,
        }, `seed-related-${index}`);
      }
    });
    const bounded = createPrivateCaptureService({
      database: db, coach, transcribe, now: () => NOW, createId: () => ids.shift()!,
      getProfileId: async () => 'profile-1', audioFiles,
      contextLimits: { maxCharacters: 20_000, maxEstimatedTokens: 20_000,
        memoryCandidateLimit: 50, evidenceCandidateLimit: 4 },
    });
    await bounded.savePrivateDraft({ conversationId: 'private-only', content: 'Do not submit.' });
    expect(coach).not.toHaveBeenCalled();
    coach.mockImplementationOnce(async (request) => {
      expect(request.context.evidence).toHaveLength(4);
      expect(request.context.evidence.every((item) => item.actionIds.includes('action-related'))).toBe(true);
      return { ...coachingResponse(request), proposals: [] };
    });
    await bounded.submitText({ conversationId: 'bounded-related', content: 'No matching vocabulary.' });
  });

  test.each([
    ['goal', {
      kind: 'goal' as const,
      title: 'Lead product strategy',
      description: 'Own the next roadmap decision.',
      priority: 'high' as const,
      targetDate: null,
      supersedesId: null,
    }],
    ['action', {
      kind: 'action' as const,
      title: 'Document the roadmap decision',
      description: null,
      priority: 'medium' as const,
      dueAt: null,
      goalId: null,
      supersedesId: null,
    }],
    ['evidence', {
      kind: 'evidence' as const,
      statement: 'Facilitated roadmap alignment.',
      occurredAt: NOW,
      goalIds: [],
      actionIds: [],
    }],
  ])('stages and applies a confirmed first-class %s outcome with local provenance', async (kind, outcome) => {
    coach.mockImplementationOnce(async (request) => ({
      ...coachingResponse(request),
      proposals: [{
        operation: 'propose-outcome' as const,
        candidate: outcome,
        reason: 'Keep this as a durable career outcome.',
        requiresConfirmation: true as const,
      }],
    }));

    const result = await service.submitText({
      conversationId: `outcome-${kind}`,
      content: 'This should become a durable outcome.',
    });
    expect(result.pendingProposals).toHaveLength(1);
    const outcomeId = `${result.pendingProposals[0].id}:outcome`;
    expect(await getGoal(db, outcomeId)).toBeNull();

    await service.confirmProposal({
      confirmationId: result.pendingProposals[0].id,
      localUserActionId: `confirm-${kind}`,
      actedAt: NOW,
    });

    const created = kind === 'goal'
      ? await getGoal(db, outcomeId)
      : kind === 'action'
        ? await getAction(db, outcomeId)
        : await getEvidence(db, outcomeId);
    expect(created).toEqual(expect.objectContaining({
      id: outcomeId,
      ...(kind === 'evidence'
        ? { sourceMessageIds: [result.messageId] }
        : { sourceMessageId: result.messageId }),
    }));

    await service.confirmProposal({
      confirmationId: result.pendingProposals[0].id,
      localUserActionId: `confirm-${kind}`,
      actedAt: NOW,
    });
  });

  test('failed coaching remains retryable with the same request and message IDs without duplicate rows', async () => {
    coach
      .mockRejectedValueOnce(new Error('raw provider payload must not escape'))
      .mockImplementationOnce(async (request) => coachingResponse(request));

    let failed: SubmissionFailedError | null = null;
    try {
      await service.submitText({
        conversationId: 'conversation-1',
        content: 'I need help preparing for a difficult review.',
      });
    } catch (error) {
      failed = error as SubmissionFailedError;
    }

    expect(failed).toBeInstanceOf(SubmissionFailedError);
    expect(failed?.message).not.toContain('raw provider payload');
    expect(failed?.requestId).toBe(UUIDS[0]);
    const failedRequest = await getRequest(db, failed!.requestId);
    expect(failedRequest).toEqual(expect.objectContaining({
      status: 'coaching-failed',
      error_code: 'COACHING_FAILED',
    }));

    const retried = await service.retrySubmission(failed!.requestId);

    expect(retried.requestId).toBe(failed!.requestId);
    expect(retried.messageId).toBe(failedRequest!.user_message_id);
    expect(coach.mock.calls[0][0].requestId).toBe(coach.mock.calls[1][0].requestId);
    expect(await listMessages(db, 'conversation-1')).toHaveLength(2);
    expect(await db.getFirstAsync<{ count: number }>(
      'SELECT count(*) AS count FROM coaching_requests',
    )).toEqual({ count: 1 });
  });

  test('voice is persisted before one transcription and waits for edited transcript confirmation before coaching', async () => {
    transcribe.mockImplementationOnce(async (input: { requestId: string; audioUri: string }) => {
      const request = await getRequest(db, UUIDS[0]);
      expect(request).toEqual(expect.objectContaining({
        status: 'transcription-pending',
        audio_uri: `file:///documents/taisa-audio/${UUIDS[0]}-recording.m4a`,
        transcription_request_id: input.requestId,
      }));
      expect(input.audioUri).toBe(`file:///documents/taisa-audio/${UUIDS[0]}-recording.m4a`);
      return {
        transcript: 'The roadmap conversation left me uncertain.',
        durationSeconds: 18,
        usage: {
          provider: 'openai' as const,
          model: 'fixture-transcription',
          audioSeconds: 18,
          estimatedCostUsd: 0.0018,
        },
      };
    });

    const voice = await service.submitVoice({
      conversationId: 'conversation-1',
      audioUri: 'file:///private/recording.m4a',
      durationSeconds: 18,
    });

    expect(voice.status).toBe('transcript-confirmation-required');
    expect(coach).not.toHaveBeenCalled();
    expect(transcribe).toHaveBeenCalledTimes(1);
    expect((await listMessages(db, 'conversation-1'))[0]).toEqual(expect.objectContaining({
      id: voice.messageId,
      lifecycle: 'pending',
      content: 'The roadmap conversation left me uncertain.',
    }));
    expect(await getRequest(db, voice.requestId)).toEqual(expect.objectContaining({
      status: 'transcript-confirmation-required',
      audio_uri: null,
    }));
    expect(audioFiles.deleteRecording).toHaveBeenCalledWith(
      `file:///documents/taisa-audio/${UUIDS[0]}-recording.m4a`,
    );
    expect(await listAudioCleanupQueue(db)).toEqual([]);

    await service.updateTranscript({
      requestId: voice.requestId,
      transcript: 'The roadmap conversation made me uncertain.',
    });
    await service.updateTranscript({
      requestId: voice.requestId,
      transcript: 'The roadmap conversation made me question the current direction.',
    });
    const completed = await service.confirmTranscript({ requestId: voice.requestId });

    expect(completed.requestId).toBe(voice.requestId);
    expect(coach).toHaveBeenCalledTimes(1);
    expect(transcribe).toHaveBeenCalledTimes(1);
    expect(coach.mock.calls[0][0].input).toBe(
      'The roadmap conversation made me question the current direction.',
    );
    expect(await getRequest(db, voice.requestId)).toEqual(expect.objectContaining({
      status: 'completed',
      transcript_confirmed_at: NOW,
    }));
  });

  test('transcription retry reuses the persisted request, message, and audio without recording or duplicating', async () => {
    transcribe
      .mockRejectedValueOnce(new Error('provider detail'))
      .mockImplementationOnce(async () => ({
        transcript: 'Recovered transcript',
        durationSeconds: 18,
        usage: {
          provider: 'openai' as const,
          model: 'fixture-transcription',
          audioSeconds: 18,
          estimatedCostUsd: 0.0018,
        },
      }));

    let failed: SubmissionFailedError | null = null;
    try {
      await service.submitVoice({
        conversationId: 'conversation-1',
        audioUri: 'file:///private/original.m4a',
        durationSeconds: 18,
      });
    } catch (error) {
      failed = error as SubmissionFailedError;
    }
    const before = await getRequest(db, failed!.requestId);

    const retried = await service.retrySubmission(failed!.requestId);

    expect(retried.status).toBe('transcript-confirmation-required');
    expect(transcribe).toHaveBeenCalledTimes(2);
    expect(transcribe.mock.calls[0][0]).toEqual(transcribe.mock.calls[1][0]);
    expect((await getRequest(db, failed!.requestId))?.user_message_id).toBe(before?.user_message_id);
    expect((await getRequest(db, failed!.requestId))?.audio_uri).toBeNull();
    expect(await listMessages(db, 'conversation-1')).toHaveLength(1);
    expect(coach).not.toHaveBeenCalled();
  });

  test('proposal confirmation is authorized only by an explicit local action and applies the staged governed payload once', async () => {
    const result = await service.submitText({
      conversationId: 'conversation-1',
      content: 'I may prefer Staff IC work.',
    });
    const pending = await db.getFirstAsync<{ id: string; status: string }>(
      'SELECT id, status FROM memory_confirmations',
    );
    expect(pending?.status).toBe('pending');

    await service.confirmProposal({
      confirmationId: pending!.id,
      localUserActionId: 'explicit-ui-action-1',
      actedAt: NOW,
    });
    await service.confirmProposal({
      confirmationId: pending!.id,
      localUserActionId: 'explicit-ui-action-1',
      actedAt: NOW,
    });

    expect(await db.getFirstAsync(
      'SELECT status, local_user_action_kind FROM memory_confirmations WHERE id = $id',
      { $id: pending!.id },
    )).toEqual({ status: 'consumed', local_user_action_kind: 'explicit-confirm' });
    expect(await db.getFirstAsync(
      'SELECT lifecycle, provenance FROM memory_items',
    )).toEqual({ lifecycle: 'active', provenance: 'ai-inferred' });
    expect(await db.getFirstAsync<{ count: number }>(
      'SELECT count(*) AS count FROM memory_items',
    )).toEqual({ count: 1 });
    expect(result.pendingProposalIds).toEqual([pending!.id]);
  });

  test('a conflicting proposal remains a clarification and generic confirmation cannot supersede it', async () => {
    await seedOldDirection(db);
    coach.mockImplementationOnce(async (request) => conflictingResponse(request));
    const result = await service.submitText({
      conversationId: 'conversation-1',
      content: 'I now want to remain a Staff IC.',
      intentId: 'clarification-intent',
    });
    expect(result.pendingProposals).toEqual([
      expect.objectContaining({
        kind: 'clarification',
        question: expect.stringContaining('replace that direction, pause it, or sit alongside it'),
      }),
    ]);
    const restarted = createPrivateCaptureService({
      database: db,
      coach,
      transcribe,
      now: () => NOW,
      createId: () => ids.shift()!,
      getProfileId: async () => 'profile-1',
      audioFiles,
    });
    expect((await restarted.hydrateConversation('conversation-1')).pendingProposals).toEqual([
      expect.objectContaining({
        kind: 'clarification',
        question: result.pendingProposals[0].question,
      }),
    ]);

    await expect(service.confirmProposal({
      confirmationId: result.pendingProposalIds[0],
      localUserActionId: 'generic-confirm-action',
      actedAt: NOW,
    })).rejects.toThrow('requires a replace, pause, or coexist choice');
    expect((await getMemory(db, 'old-direction'))?.lifecycle).toBe('active');
    expect(await db.getFirstAsync(
      'SELECT status FROM memory_confirmations WHERE id = $id',
      { $id: result.pendingProposalIds[0] },
    )).toEqual({ status: 'pending' });
  });

  test.each([
    ['replace', 'superseded', 'old-direction'],
    ['pause', 'paused', null],
    ['coexist', 'active', null],
  ] as const)(
    'clarification choice %s applies one complete governed resolution',
    async (choice, expectedOldLifecycle, expectedSupersedesId) => {
      await seedOldDirection(db);
      coach.mockImplementationOnce(async (request) => conflictingResponse(request));
      const result = await service.submitText({
        conversationId: 'conversation-1',
        content: 'I now want to remain a Staff IC.',
        intentId: `clarification-${choice}`,
      });
      const confirmationId = result.pendingProposalIds[0];

      await service.resolveClarification({
        confirmationId,
        choice,
        localUserActionId: `choice-${choice}`,
        actedAt: NOW,
      });

      expect((await getMemory(db, 'old-direction'))?.lifecycle).toBe(expectedOldLifecycle);
      const successor = await db.getFirstAsync<{
        lifecycle: string;
        supersedes_id: string | null;
      }>('SELECT lifecycle, supersedes_id FROM memory_items WHERE id != $oldId', {
        $oldId: 'old-direction',
      });
      expect(successor).toEqual({ lifecycle: 'active', supersedes_id: expectedSupersedesId });
      const confirmation = await db.getFirstAsync<{
        status: string;
        resolution_json: string;
      }>('SELECT status, resolution_json FROM memory_confirmations WHERE id = $id', {
        $id: confirmationId,
      });
      expect(confirmation?.status).toBe('consumed');
      expect(confirmation?.resolution_json).toContain(`"choice":"${choice}"`);
    },
  );

  test('clarification presentation survives restart even if predecessor state changes', async () => {
    await seedOldDirection(db);
    coach.mockImplementationOnce(async (request) => conflictingResponse(request));
    const result = await service.submitText({
      conversationId: 'conversation-1',
      content: 'I now want to remain a Staff IC.',
      intentId: 'durable-clarification-presentation',
    });
    const oldDirection = (await getMemory(db, 'old-direction'))!;
    await db.withTransaction((transaction) => updateMemory(
      transaction,
      {
        ...oldDirection,
        lifecycle: 'completed',
        statusChangedAt: '2026-08-10T10:00:00.000Z',
        updatedAt: '2026-08-10T10:00:00.000Z',
      },
      'change-old-direction-after-stage',
    ));

    expect((await service.hydrateConversation('conversation-1')).pendingProposals).toEqual([
      expect.objectContaining({
        id: result.pendingProposalIds[0],
        kind: 'clarification',
        question: result.pendingProposals[0].question,
      }),
    ]);
  });

  test('clarification resolution rolls confirmation, successor, and predecessor back atomically', async () => {
    await seedOldDirection(db);
    coach.mockImplementationOnce(async (request) => conflictingResponse(request));
    const result = await service.submitText({
      conversationId: 'conversation-1',
      content: 'I now want to remain a Staff IC.',
      intentId: 'clarification-rollback',
    });
    await db.execAsync(`CREATE TRIGGER force_clarification_failure
      BEFORE UPDATE ON memory_items WHEN OLD.id = 'old-direction'
      BEGIN SELECT RAISE(ABORT, 'forced clarification failure'); END`);

    let failure: unknown = null;
    try {
      await service.resolveClarification({
        confirmationId: result.pendingProposalIds[0],
        choice: 'pause',
        localUserActionId: 'choice-pause-rollback',
        actedAt: NOW,
      });
    } catch (error) {
      failure = error;
    }
    expect(failure).not.toBeNull();

    expect((await getMemory(db, 'old-direction'))?.lifecycle).toBe('active');
    expect(await db.getFirstAsync<{ count: number }>(
      'SELECT count(*) AS count FROM memory_items',
    )).toEqual({ count: 1 });
    expect(await db.getFirstAsync(
      'SELECT status FROM memory_confirmations WHERE id = $id',
      { $id: result.pendingProposalIds[0] },
    )).toEqual({ status: 'pending' });
  });

  test('oversize text is rejected before any request, message, or network state exists', async () => {
    await expect(service.submitText({
        conversationId: 'conversation-1',
        content: 'x'.repeat(4_001),
        intentId: 'oversize-text-intent',
      })).rejects.toBeInstanceOf(SubmissionValidationError);
    expect(coach).not.toHaveBeenCalled();
    expect(await db.getFirstAsync('SELECT id FROM coaching_requests')).toBeNull();
    expect(await db.getFirstAsync('SELECT id FROM messages')).toBeNull();
  });

  test('the same concurrent text intent persists and charges exactly once', async () => {
    let release!: () => void;
    const gate = new Promise<void>((resolve) => { release = resolve; });
    coach.mockImplementationOnce(async (request) => {
      await gate;
      return coachingResponse(request);
    });

    const input = {
      conversationId: 'conversation-1',
      content: 'Help me prepare for the review.',
      intentId: 'submit-button-intent-1',
    };
    const first = service.submitText(input);
    const second = service.submitText(input);
    expect(second).toBe(first);
    release();
    const [left, right] = await Promise.all([first, second]);

    expect(left).toEqual(right);
    expect(coach).toHaveBeenCalledTimes(1);
    expect(await db.getFirstAsync<{ count: number }>(
      'SELECT count(*) AS count FROM coaching_requests',
    )).toEqual({ count: 1 });
    expect((await listMessages(db, 'conversation-1'))).toHaveLength(2);
  });

  test('retrying a persisted pending request joins its original paid call', async () => {
    let release!: () => void;
    let markStarted!: () => void;
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const started = new Promise<void>((resolve) => { markStarted = resolve; });
    coach.mockImplementationOnce(async (request) => {
      markStarted();
      await gate;
      return coachingResponse(request);
    });

    const original = service.submitText({
      conversationId: 'conversation-1',
      content: 'Do not duplicate this pending paid call.',
      intentId: 'pending-retry-intent',
    });
    await started;
    const pending = await db.getFirstAsync<{ id: string; attempt_count: number }>(
      'SELECT id, attempt_count FROM coaching_requests',
    );
    const retry = service.retrySubmission(pending!.id);
    release();
    const [left, right] = await Promise.all([original, retry]);

    expect(left).toEqual(right);
    expect(coach).toHaveBeenCalledTimes(1);
    expect(await db.getFirstAsync(
      'SELECT attempt_count FROM coaching_requests WHERE id = $id',
      { $id: pending!.id },
    )).toEqual({ attempt_count: 1 });
  });

  test('voice is copied into app-owned durable storage before request persistence and concurrent intent is deduplicated', async () => {
    let release!: () => void;
    const gate = new Promise<void>((resolve) => { release = resolve; });
    audioFiles.persistRecording.mockImplementationOnce(async ({ requestId }) => {
      expect(await getRequest(db, requestId)).toBeNull();
      return `file:///documents/taisa-audio/${requestId}.m4a`;
    });
    transcribe.mockImplementationOnce(async () => {
      await gate;
      return {
        transcript: 'A durable recording transcript.',
        durationSeconds: 10,
        usage: {
          provider: 'openai' as const,
          model: 'fixture-transcription',
          audioSeconds: 10,
          estimatedCostUsd: 0.001,
        },
      };
    });
    const input = {
      conversationId: 'conversation-1',
      audioUri: 'file:///cache/temporary.m4a',
      durationSeconds: 10,
      intentId: 'voice-submit-intent-1',
    };
    const first = service.submitVoice(input);
    const second = service.submitVoice(input);
    expect(second).toBe(first);
    release();
    const [left, right] = await Promise.all([first, second]);

    expect(left).toEqual(right);
    expect(audioFiles.persistRecording).toHaveBeenCalledTimes(1);
    expect(transcribe).toHaveBeenCalledTimes(1);
    expect(transcribe.mock.calls[0][0].audioUri).toBe(
      `file:///documents/taisa-audio/${left.requestId}.m4a`,
    );
    expect(await db.getFirstAsync<{ count: number }>(
      'SELECT count(*) AS count FROM coaching_requests',
    )).toEqual({ count: 1 });
  });

  test('rapid transcript confirmation returns one in-flight result and makes one coaching call', async () => {
    const voice = await service.submitVoice({
      conversationId: 'conversation-1',
      audioUri: 'file:///cache/confirm-once.m4a',
      durationSeconds: 10,
      intentId: 'confirm-once-voice-intent',
    });
    let release!: () => void;
    const gate = new Promise<void>((resolve) => { release = resolve; });
    coach.mockImplementationOnce(async (request) => {
      await gate;
      return coachingResponse(request);
    });

    const first = service.confirmTranscript({ requestId: voice.requestId });
    const second = service.confirmTranscript({ requestId: voice.requestId });
    expect(second).toBe(first);
    release();
    const [left, right] = await Promise.all([first, second]);

    expect(left).toEqual(right);
    expect(coach).toHaveBeenCalledTimes(1);
    expect(transcribe).toHaveBeenCalledTimes(1);
  });

  test('oversize voice transcript stays editable on the same request until corrected and confirmed', async () => {
    transcribe.mockResolvedValueOnce({
      transcript: 'x'.repeat(4_001),
      durationSeconds: 18,
      usage: {
        provider: 'openai' as const,
        model: 'fixture-transcription',
        audioSeconds: 18,
        estimatedCostUsd: 0.0018,
      },
    });
    const voice = await service.submitVoice({
      conversationId: 'conversation-1',
      audioUri: 'file:///cache/oversize.m4a',
      durationSeconds: 18,
      intentId: 'oversize-voice-intent',
    });

    await expect(service.confirmTranscript({ requestId: voice.requestId }))
      .rejects.toBeInstanceOf(SubmissionValidationError);
    expect((await getRequest(db, voice.requestId))?.status)
      .toBe('transcript-confirmation-required');
    expect(coach).not.toHaveBeenCalled();

    await service.updateTranscript({
      requestId: voice.requestId,
      transcript: 'I corrected this transcript before submitting it.',
    });
    const completed = await service.confirmTranscript({ requestId: voice.requestId });
    expect(completed.requestId).toBe(voice.requestId);
    expect(coach).toHaveBeenCalledTimes(1);
    expect(coach.mock.calls[0][0].input).toBe(
      'I corrected this transcript before submitting it.',
    );
  });

  test('restart hydration restores transcript review and pending proposals without a network call', async () => {
    const voice = await service.submitVoice({
      conversationId: 'voice-conversation',
      audioUri: 'file:///cache/restart.m4a',
      durationSeconds: 18,
      intentId: 'restart-voice-intent',
    });
    coach.mockClear();
    transcribe.mockClear();
    const restarted = createPrivateCaptureService({
      database: db,
      coach,
      transcribe,
      now: () => NOW,
      createId: () => ids.shift()!,
      getProfileId: async () => 'profile-1',
      audioFiles,
    });

    expect(await restarted.hydrateConversation('voice-conversation')).toEqual(
      expect.objectContaining({
        requestId: voice.requestId,
        messageId: voice.messageId,
        requestStatus: 'transcript-confirmation-required',
        transcript: 'The roadmap conversation left me uncertain.',
      }),
    );
    expect(coach).not.toHaveBeenCalled();
    expect(transcribe).not.toHaveBeenCalled();

    await service.submitText({
      conversationId: 'proposal-conversation',
      content: 'I may prefer Staff IC work.',
      intentId: 'proposal-restart-intent',
    });
    coach.mockClear();
    const restored = await restarted.hydrateConversation('proposal-conversation');
    expect(restored.requestStatus).toBe('completed');
    expect(restored.pendingProposals).toHaveLength(1);
    expect(coach).not.toHaveBeenCalled();
  });

  test('restart hydration rediscovers a retryable failed request without making a network call', async () => {
    coach.mockRejectedValueOnce(new Error('provider detail'));
    let requestId = '';
    try {
      await service.submitText({
        conversationId: 'failed-conversation',
        content: 'Help me recover this interrupted thought.',
        intentId: 'failed-restart-intent',
      });
    } catch (error) {
      requestId = (error as SubmissionFailedError).requestId;
    }
    coach.mockClear();
    const restarted = createPrivateCaptureService({
      database: db,
      coach,
      transcribe,
      now: () => NOW,
      createId: () => ids.shift()!,
      getProfileId: async () => 'profile-1',
      audioFiles,
    });

    expect(await restarted.hydrateConversation('failed-conversation')).toEqual(
      expect.objectContaining({
        requestId,
        requestStatus: 'coaching-failed',
      }),
    );
    expect(coach).not.toHaveBeenCalled();
  });

  test('a newer completed turn cannot mask an older actionable request on restart', async () => {
    coach.mockRejectedValueOnce(new Error('first turn failed'));
    let failedRequestId = '';
    try {
      await service.submitText({
        conversationId: 'multi-turn-conversation',
        content: 'The first turn must remain retryable.',
        intentId: 'older-failed-intent',
      });
    } catch (error) {
      failedRequestId = (error as SubmissionFailedError).requestId;
    }
    await service.submitText({
      conversationId: 'multi-turn-conversation',
      content: 'A later turn completed successfully.',
      intentId: 'newer-completed-intent',
    });
    coach.mockClear();

    expect(await service.hydrateConversation('multi-turn-conversation')).toEqual(
      expect.objectContaining({
        requestId: failedRequestId,
        requestStatus: 'coaching-failed',
      }),
    );
    expect(coach).not.toHaveBeenCalled();
  });

  test('discarding a recording retires its temporary or durable file', async () => {
    await service.discardRecording('file:///cache/abandoned.m4a');
    expect(audioFiles.deleteRecording).toHaveBeenCalledWith('file:///cache/abandoned.m4a');
    expect(await listAudioCleanupQueue(db)).toEqual([]);
  });

  test('concurrent discard paths share one filesystem attempt for the same recording', async () => {
    const audioUri = 'file:///cache/close-replacement-race.m4a';
    let releaseDelete!: () => void;
    let reportDeleteStarted!: () => void;
    const deleteStarted = new Promise<void>((resolve) => {
      reportDeleteStarted = resolve;
    });
    audioFiles.deleteRecording.mockImplementation(() => new Promise<void>((resolve) => {
      releaseDelete = resolve;
      reportDeleteStarted();
    }));

    const replacement = service.discardRecording(audioUri);
    const close = service.discardRecording(audioUri);
    await deleteStarted;
    releaseDelete();
    await Promise.all([replacement, close]);

    expect(audioFiles.deleteRecording).toHaveBeenCalledTimes(1);
    expect(await listAudioCleanupQueue(db)).toEqual([]);
  });

  test('a failed recording deletion is durably queued and drains exactly once after restart', async () => {
    const audioUri = 'file:///cache/restart-cleanup.m4a';
    audioFiles.deleteRecording
      .mockRejectedValueOnce(new Error('private filesystem detail'))
      .mockResolvedValue(undefined);

    await service.discardRecording(audioUri);

    expect(await listAudioCleanupQueue(db)).toEqual([
      expect.objectContaining({
        audioUri,
        attemptCount: 1,
        lastErrorCode: 'AUDIO_DELETE_FAILED',
      }),
    ]);
    const restarted = createPrivateCaptureService({
      database: db,
      coach,
      transcribe,
      now: () => NOW,
      createId: () => ids.shift()!,
      getProfileId: async () => 'profile-1',
      audioFiles,
    });

    await restarted.drainAudioCleanupQueue();
    await restarted.drainAudioCleanupQueue();

    expect(audioFiles.deleteRecording).toHaveBeenCalledTimes(2);
    expect(audioFiles.deleteRecording).toHaveBeenLastCalledWith(audioUri);
    expect(await listAudioCleanupQueue(db)).toEqual([]);
  });

  test('cleanup drain never deletes audio referenced by an active coaching request', async () => {
    transcribe.mockRejectedValueOnce(new Error('transcription unavailable'));
    let failedRequestId = '';
    try {
      await service.submitVoice({
        conversationId: 'active-audio-conversation',
        audioUri: 'file:///cache/active-source.m4a',
        durationSeconds: 18,
        intentId: 'active-audio-intent',
      });
    } catch (error) {
      failedRequestId = (error as SubmissionFailedError).requestId;
    }
    const durableUri = (await getRequest(db, failedRequestId))!.audio_uri!;
    await db.withTransaction((transaction) => enqueueAudioCleanup(transaction, {
      audioUri: durableUri,
      enqueuedAt: NOW,
    }));
    audioFiles.deleteRecording.mockClear();

    await service.drainAudioCleanupQueue();

    expect(audioFiles.deleteRecording).not.toHaveBeenCalledWith(durableUri);
    expect(await listAudioCleanupQueue(db)).toEqual([
      expect.objectContaining({ audioUri: durableUri, attemptCount: 0 }),
    ]);
  });

  test('concurrent cleanup drains share one filesystem attempt for the same queued URI', async () => {
    const audioUri = 'file:///cache/concurrent-cleanup.m4a';
    await db.withTransaction((transaction) => enqueueAudioCleanup(transaction, {
      audioUri,
      enqueuedAt: NOW,
    }));
    let releaseDelete!: () => void;
    let reportDeleteStarted!: () => void;
    const deleteStarted = new Promise<void>((resolve) => {
      reportDeleteStarted = resolve;
    });
    audioFiles.deleteRecording.mockImplementationOnce(() => new Promise<void>((resolve) => {
      releaseDelete = resolve;
      reportDeleteStarted();
    }));

    const first = service.drainAudioCleanupQueue();
    const second = service.drainAudioCleanupQueue();

    expect(second).toBe(first);
    await deleteStarted;
    expect(audioFiles.deleteRecording).toHaveBeenCalledTimes(1);
    releaseDelete();
    await Promise.all([first, second]);
    expect(await listAudioCleanupQueue(db)).toEqual([]);
  });

  test('temporary source cleanup after voice submit is recoverable without failing transcription', async () => {
    const sourceUri = 'file:///cache/source-delete-fails.m4a';
    audioFiles.deleteRecording.mockRejectedValueOnce(new Error('source delete detail'));

    await expect(service.submitVoice({
      conversationId: 'source-cleanup-conversation',
      audioUri: sourceUri,
      durationSeconds: 18,
      intentId: 'source-cleanup-intent',
    })).resolves.toEqual(expect.objectContaining({
      status: 'transcript-confirmation-required',
    }));

    expect(await listAudioCleanupQueue(db)).toEqual([
      expect.objectContaining({
        audioUri: sourceUri,
        attemptCount: 1,
        lastErrorCode: 'AUDIO_DELETE_FAILED',
      }),
    ]);
  });

  test('durable copy cleanup after local request rollback keeps a recoverable pointer', async () => {
    const durableUri = 'file:///documents/taisa-audio/rolled-back-request.m4a';
    audioFiles.persistRecording.mockResolvedValueOnce(durableUri);
    audioFiles.deleteRecording.mockRejectedValueOnce(new Error('durable delete detail'));
    await db.execAsync(`CREATE TRIGGER force_voice_request_insert_failure
      BEFORE INSERT ON coaching_requests
      BEGIN SELECT RAISE(ABORT, 'forced voice request insert failure'); END`);

    let requestInsertFailure: unknown;
    try {
      await service.submitVoice({
        conversationId: 'rolled-back-voice-conversation',
        audioUri: 'file:///cache/rolled-back-source.m4a',
        durationSeconds: 18,
        intentId: 'rolled-back-voice-intent',
      });
    } catch (error) {
      requestInsertFailure = error;
    }
    expect(String((requestInsertFailure as { message?: string })?.message))
      .toContain('forced voice request insert failure');

    expect(await listAudioCleanupQueue(db)).toEqual([
      expect.objectContaining({
        audioUri: durableUri,
        attemptCount: 1,
        lastErrorCode: 'AUDIO_DELETE_FAILED',
      }),
    ]);
  });

  test('recording again after transcription abandons paid-request state after audio was retired', async () => {
    const voice = await service.submitVoice({
      conversationId: 'conversation-1',
      audioUri: 'file:///cache/abandon-durable.m4a',
      durationSeconds: 18,
      intentId: 'abandon-durable-intent',
    });
    expect((await getRequest(db, voice.requestId))!.audio_uri).toBeNull();
    audioFiles.deleteRecording.mockClear();

    await service.abandonVoiceSubmission(voice.requestId);

    expect(audioFiles.deleteRecording).not.toHaveBeenCalled();
    expect(await getRequest(db, voice.requestId)).toEqual(expect.objectContaining({
      status: 'abandoned',
      audio_uri: null,
    }));
    expect((await listMessages(db, 'conversation-1'))[0].lifecycle).toBe('private');
    expect(await service.hydrateConversation('conversation-1')).toEqual(
      expect.objectContaining({ requestId: null, requestStatus: null }),
    );
  });

  test('durable audio retirement queues a failed delete and clears the request pointer safely', async () => {
    const durableUri = `file:///documents/taisa-audio/${UUIDS[0]}-delete-retry.m4a`;
    audioFiles.deleteRecording
      .mockResolvedValueOnce(undefined)
      .mockRejectedValueOnce(new Error('filesystem unavailable'));

    const voice = await service.submitVoice({
      conversationId: 'conversation-1',
      audioUri: 'file:///cache/delete-retry.m4a',
      durationSeconds: 18,
      intentId: 'delete-retry-intent',
    });

    expect(await getRequest(db, voice.requestId)).toEqual(expect.objectContaining({
      status: 'transcript-confirmation-required',
      audio_uri: null,
    }));
    expect(await listAudioCleanupQueue(db)).toEqual([
      expect.objectContaining({ audioUri: durableUri, attemptCount: 1 }),
    ]);

    audioFiles.deleteRecording.mockResolvedValue(undefined);
    await service.drainAudioCleanupQueue();
    expect(await listAudioCleanupQueue(db)).toEqual([]);
  });

  test('durable audio retirement resumes after the post-delete database update rolls back', async () => {
    transcribe.mockRejectedValueOnce(new Error('transcription unavailable'));
    let failedRequestId = '';
    try {
      await service.submitVoice({
        conversationId: 'conversation-1',
        audioUri: 'file:///cache/database-retry.m4a',
        durationSeconds: 18,
        intentId: 'database-retry-intent',
      });
    } catch (error) {
      failedRequestId = (error as SubmissionFailedError).requestId;
    }
    await db.execAsync(`CREATE TRIGGER force_audio_retirement_failure
      BEFORE UPDATE ON coaching_requests
      WHEN OLD.id = '${failedRequestId}' AND NEW.audio_uri IS NULL
      BEGIN SELECT RAISE(ABORT, 'forced audio retirement failure'); END`);
    let currentTime = NOW;
    const restarted = createPrivateCaptureService({
      database: db,
      coach,
      transcribe,
      now: () => currentTime,
      createId: () => ids.shift()!,
      getProfileId: async () => 'profile-1',
      audioFiles,
    });

    let retirementFailure: unknown;
    try {
      await restarted.abandonVoiceSubmission(failedRequestId);
    } catch (error) {
      retirementFailure = error;
    }
    expect(String((retirementFailure as { message?: string })?.message))
      .toContain('forced audio retirement failure');
    expect(await getRequest(db, failedRequestId)).toEqual(expect.objectContaining({
      status: 'abandoned',
      audio_uri: expect.any(String),
    }));

    await db.execAsync('DROP TRIGGER force_audio_retirement_failure');
    currentTime = '2026-08-10T10:00:00.000Z';
    await restarted.drainAudioCleanupQueue();
    expect((await getRequest(db, failedRequestId))?.audio_uri).toBeNull();
    expect(await listAudioCleanupQueue(db)).toEqual([]);
  });

  test('assistant response, usage, and governed proposals roll back together when local proposal staging fails', async () => {
    coach.mockImplementationOnce(async (request) => {
      await db.execAsync(`CREATE TRIGGER force_confirmation_failure
        BEFORE INSERT ON memory_confirmations
        BEGIN SELECT RAISE(ABORT, 'forced confirmation failure'); END`);
      return coachingResponse(request);
    });

    let failure: SubmissionFailedError | null = null;
    try {
      await service.submitText({
        conversationId: 'conversation-1',
        content: 'I may prefer Staff IC work.',
      });
    } catch (error) {
      failure = error as SubmissionFailedError;
    }

    expect(failure).toBeInstanceOf(SubmissionFailedError);
    expect(await db.getFirstAsync('SELECT id FROM usage_receipts')).toBeNull();
    expect(await db.getFirstAsync('SELECT id FROM memory_confirmations')).toBeNull();
    expect((await listMessages(db, 'conversation-1'))).toEqual([
      expect.objectContaining({ role: 'user', lifecycle: 'failed' }),
    ]);
  });

  test('coaching retry after a confirmed voice transcript never retranscribes the persisted audio', async () => {
    coach
      .mockRejectedValueOnce(new Error('first coaching failure'))
      .mockImplementationOnce(async (request) => coachingResponse(request));
    const voice = await service.submitVoice({
      conversationId: 'conversation-1',
      audioUri: 'file:///private/original.m4a',
      durationSeconds: 18,
    });

    await expect(service.confirmTranscript({ requestId: voice.requestId }))
      .rejects.toBeInstanceOf(SubmissionFailedError);
    const completed = await service.retrySubmission(voice.requestId);

    expect(completed.status).toBe('completed');
    expect(transcribe).toHaveBeenCalledTimes(1);
    expect(coach).toHaveBeenCalledTimes(2);
    expect(coach.mock.calls[0][0].requestId).toBe(coach.mock.calls[1][0].requestId);
  });

  test('a failed voice coaching request can be edited and reconfirmed on the same request and message', async () => {
    let currentTime = NOW;
    const mutableClockService = createPrivateCaptureService({
      database: db,
      coach,
      transcribe,
      now: () => currentTime,
      createId: () => ids.shift()!,
      getProfileId: async () => 'profile-1',
      audioFiles,
    });
    coach
      .mockRejectedValueOnce(new Error('first coaching failure'))
      .mockImplementationOnce(async (request) => coachingResponse(request));
    const voice = await mutableClockService.submitVoice({
      conversationId: 'conversation-1',
      audioUri: 'file:///cache/edit-after-failure.m4a',
      durationSeconds: 18,
      intentId: 'edit-after-failure-intent',
    });
    await expect(mutableClockService.confirmTranscript({ requestId: voice.requestId }))
      .rejects.toBeInstanceOf(SubmissionFailedError);

    currentTime = '2026-08-10T10:00:00.000Z';
    await mutableClockService.updateTranscript({
      requestId: voice.requestId,
      transcript: 'A corrected thought after the failed coaching attempt.',
    });
    const completed = await mutableClockService.confirmTranscript({ requestId: voice.requestId });

    expect(completed.requestId).toBe(voice.requestId);
    expect(completed.messageId).toBe(voice.messageId);
    expect(transcribe).toHaveBeenCalledTimes(1);
    expect(coach).toHaveBeenCalledTimes(2);
    expect((await getRequest(db, voice.requestId))?.attempt_count).toBe(2);
    expect(coach.mock.calls[1][0].input).toBe(
      'A corrected thought after the failed coaching attempt.',
    );
  });
});
