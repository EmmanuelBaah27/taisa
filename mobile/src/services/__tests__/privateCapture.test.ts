import type { CoachingRequest, CoachingResponse } from '@taisa/shared';

import type { RepositoryTransaction } from '../../db/types';
import { listMessages } from '../../repositories/conversationRepository';
import {
  createTestDatabase,
  type TestDatabase,
} from '../../repositories/__tests__/testDatabase';
import {
  createPrivateCaptureService,
  type PrivateCaptureService,
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
}

async function getRequest(db: TestDatabase, id: string): Promise<RequestRow | null> {
  return db.getFirstAsync<RequestRow>(
    `SELECT id, user_message_id, transcription_request_id, status, audio_uri,
            transcript_confirmed_at, assistant_message_id, context_manifest_json, error_code
       FROM coaching_requests WHERE id = $id`,
    { $id: id },
  );
}

describe('private local capture and deliberate submission', () => {
  let db: TestDatabase;
  let coach: jest.Mock<Promise<CoachingResponse>, [CoachingRequest]>;
  let transcribe: jest.Mock;
  let service: PrivateCaptureService;
  let ids: string[];

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
    service = createPrivateCaptureService({
      database: db,
      coach,
      transcribe,
      now: () => NOW,
      createId: () => ids.shift()!,
      getProfileId: async () => 'profile-1',
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
        audio_uri: 'file:///private/recording.m4a',
        transcription_request_id: input.requestId,
      }));
      expect(input.audioUri).toBe('file:///private/recording.m4a');
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
    expect((await getRequest(db, failed!.requestId))?.audio_uri).toBe('file:///private/original.m4a');
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

  test('a local context-contract failure leaves a retryable failed message instead of a stuck pending request', async () => {
    let failure: SubmissionFailedError | null = null;
    try {
      await service.submitText({
        conversationId: 'conversation-1',
        content: 'x'.repeat(4_001),
      });
    } catch (error) {
      failure = error as SubmissionFailedError;
    }

    expect(failure).toBeInstanceOf(SubmissionFailedError);
    expect(coach).not.toHaveBeenCalled();
    expect(await getRequest(db, failure!.requestId)).toEqual(expect.objectContaining({
      status: 'coaching-failed',
      error_code: 'COACHING_FAILED',
    }));
    expect((await listMessages(db, 'conversation-1'))[0]).toEqual(expect.objectContaining({
      lifecycle: 'failed',
      content: 'x'.repeat(4_001),
    }));
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
});
