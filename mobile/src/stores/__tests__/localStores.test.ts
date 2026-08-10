import type { CoachingRequest, CoachingResponse } from '@taisa/shared';

import { getProfile } from '../../repositories/profileRepository';
import { createTestDatabase, type TestDatabase } from '../../repositories/__tests__/testDatabase';
import { createPrivateCaptureService, type PrivateCaptureService } from '../../services/privateCapture';
import { createCareerStore } from '../careerStore';
import { createChatStore } from '../chatStore';
import { createThreadStore } from '../threadStore';

const NOW = '2026-08-10T09:00:00.000Z';
const IDS = [
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000002',
  '00000000-0000-4000-8000-000000000003',
  '00000000-0000-4000-8000-000000000004',
  '00000000-0000-4000-8000-000000000005',
];

function response(request: CoachingRequest): CoachingResponse {
  return {
    requestId: request.requestId,
    reply: 'What would a good next conversation accomplish?',
    stance: 'nudge',
    proposals: [],
    usage: {
      provider: 'openai',
      model: 'fixture',
      estimatedCostUsd: 0,
    },
  };
}

describe('local-first stores', () => {
  let db: TestDatabase;
  let capture: PrivateCaptureService;
  let secureUserId: string | null;

  beforeEach(() => {
    db = createTestDatabase();
    secureUserId = null;
    const ids = [...IDS];
    capture = createPrivateCaptureService({
      database: db,
      coach: async (request) => response(request),
      transcribe: async () => { throw new Error('not used'); },
      now: () => NOW,
      createId: () => ids.shift()!,
      getProfileId: async () => secureUserId ?? 'profile-1',
      audioFiles: {
        persistRecording: async ({ sourceUri }) => sourceUri,
        deleteRecording: async (_uri: string) => undefined,
      },
    });
  });

  afterEach(() => db.close());

  test('career profile initialization and edits persist through the local profile repository', async () => {
    let mutation = 0;
    const store = createCareerStore({
      openDatabase: async () => db,
      secureStore: {
        getItemAsync: async () => secureUserId,
        setItemAsync: async (_key, value) => { secureUserId = value; },
      },
      now: () => NOW,
      createId: () => `profile-mutation-${mutation += 1}`,
    });

    await store.getState().initUser('profile-1', {
      currentRole: 'Product Designer',
      industry: 'Technology',
      yearsOfExperience: 6,
      careerStage: 'senior',
      coachingStyle: 'socratic',
      accountabilityLevel: 'moderate',
    });
    await store.getState().updateProfile({ longTermGoal: 'Become a Staff Designer' });
    await store.getState().updateProfile({ currentCompany: 'Private employer' });
    await store.getState().updateProfile({ currentCompany: null });
    store.setState({ profile: null });
    await store.getState().fetchProfile();

    expect(secureUserId).toBe('profile-1');
    expect(store.getState().profile).toEqual(expect.objectContaining({
      currentRole: 'Product Designer',
      longTermGoal: 'Become a Staff Designer',
      currentCompany: null,
    }));
    expect(await getProfile(db, 'profile-1')).toEqual(expect.objectContaining({
      currentRole: 'Product Designer',
      longTermGoal: 'Become a Staff Designer',
      currentCompany: null,
    }));
  });

  test('thread reads and sends use local conversations and the stateless capture service', async () => {
    await capture.savePrivateDraft({
      conversationId: 'conversation-1',
      content: 'A private draft',
    });
    const store = createThreadStore({
      openDatabase: async () => db,
      getCaptureService: async () => capture,
    });

    await store.getState().fetchThreads();
    await store.getState().fetchThread('conversation-1');
    await store.getState().sendMessage('conversation-1', 'Help me plan the follow-up.');

    expect(store.getState().threads).toEqual([
      expect.objectContaining({ id: 'conversation-1', title: 'A private draft' }),
    ]);
    expect(store.getState().currentMessages).toHaveLength(3);
    expect(store.getState().currentMessages.map((item) => item.content)).toEqual([
      'A private draft',
      'Help me plan the follow-up.',
      'What would a good next conversation accomplish?',
    ]);
    expect(store.getState().currentSession).toEqual(expect.objectContaining({
      pendingRequestStatus: 'completed',
      pendingProposalCount: 0,
    }));
    expect(store.getState().error).toBeNull();
  });

  test('chat actions keep only view state while private save and submit persist through the capture service', async () => {
    const store = createChatStore(async () => capture);

    await store.getState().savePrivateDraft('conversation-1', 'Private planning note');
    await store.getState().submitText('conversation-1', 'Help me decide what to do next.');

    expect(store.getState()).toEqual(expect.objectContaining({
      activeSessionId: 'conversation-1',
      activeRequestId: IDS[1],
      phase: 'responded',
      error: null,
    }));
  });

  test('chat store synchronously deduplicates a rapid submit intent and restores durable transcript review', async () => {
    let release!: () => void;
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const submitText = jest.fn(async () => {
      await gate;
      return {
        status: 'completed' as const,
        requestId: 'request-1',
        messageId: 'message-1',
        assistantMessageId: 'assistant-1',
        pendingProposalIds: [],
        pendingProposals: [],
      };
    });
    const hydrateConversation = jest.fn(async () => ({
      requestId: 'voice-request',
      messageId: 'voice-message',
      requestStatus: 'transcript-confirmation-required' as const,
      transcript: 'Restored editable transcript',
      pendingProposals: [],
    }));
    const drainAudioCleanupQueue = jest.fn(async () => undefined);
    const fake = {
      submitText,
      hydrateConversation,
      drainAudioCleanupQueue,
    } as unknown as PrivateCaptureService;
    const store = createChatStore(async () => fake);

    const first = store.getState().submitText('conversation-1', 'One intentional thought');
    const second = store.getState().submitText('conversation-1', 'One intentional thought');
    expect(second).toBe(first);
    expect(store.getState().isBusy).toBe(true);
    release();
    await Promise.all([first, second]);
    expect(submitText).toHaveBeenCalledTimes(1);
    expect(submitText).toHaveBeenCalledWith(expect.objectContaining({
      intentId: expect.any(String),
    }));
    expect(store.getState().isBusy).toBe(false);

    await store.getState().hydrateConversation('conversation-1');
    expect(hydrateConversation).toHaveBeenCalledWith('conversation-1');
    expect(store.getState()).toEqual(expect.objectContaining({
      activeRequestId: 'voice-request',
      activeMessageId: 'voice-message',
      transcript: 'Restored editable transcript',
      phase: 'transcript-review',
    }));

    await store.getState().drainAudioCleanupQueue();
    expect(drainAudioCleanupQueue).toHaveBeenCalledTimes(1);
  });

  test('a fresh chat store restores the same durable voice request without provider calls', async () => {
    const beforeRestartTranscribe = jest.fn(async () => ({
      transcript: 'A transcript that survives process death',
      durationSeconds: 21,
      usage: {
        provider: 'openai' as const,
        model: 'fixture-transcription',
        audioSeconds: 21,
        estimatedCostUsd: 0.001,
      },
    }));
    const beforeRestartCoach = jest.fn(async (request: CoachingRequest) => response(request));
    const beforeRestartIds = [...IDS];
    const beforeRestartService = createPrivateCaptureService({
      database: db,
      coach: beforeRestartCoach,
      transcribe: beforeRestartTranscribe,
      now: () => NOW,
      createId: () => beforeRestartIds.shift()!,
      getProfileId: async () => 'profile-1',
      audioFiles: {
        persistRecording: async () => 'file:///documents/taisa-audio/durable-request.m4a',
        deleteRecording: async () => undefined,
      },
    });
    const beforeRestartStore = createChatStore(async () => beforeRestartService);

    await beforeRestartStore.getState().submitVoice(
      'conversation-after-process-death',
      'file:///cache/temporary-recording.m4a',
      21,
    );
    const durableRequestId = beforeRestartStore.getState().activeRequestId;
    const durableMessageId = beforeRestartStore.getState().activeMessageId;

    const afterRestartCoach = jest.fn(async () => { throw new Error('must stay offline'); });
    const afterRestartTranscribe = jest.fn(async () => { throw new Error('must stay offline'); });
    const afterRestartService = createPrivateCaptureService({
      database: db,
      coach: afterRestartCoach,
      transcribe: afterRestartTranscribe,
      now: () => NOW,
      createId: () => 'unused-after-restart-id',
      getProfileId: async () => 'profile-1',
      audioFiles: {
        persistRecording: async () => { throw new Error('must stay offline'); },
        deleteRecording: async () => undefined,
      },
    });
    const afterRestartStore = createChatStore(async () => afterRestartService);

    expect(afterRestartStore.getState().activeSessionId).toBeNull();
    await afterRestartStore.getState().hydrateConversation('conversation-after-process-death');

    expect(afterRestartStore.getState()).toEqual(expect.objectContaining({
      activeSessionId: 'conversation-after-process-death',
      activeRequestId: durableRequestId,
      activeMessageId: durableMessageId,
      transcript: 'A transcript that survives process death',
      phase: 'transcript-review',
    }));
    expect(afterRestartCoach).not.toHaveBeenCalled();
    expect(afterRestartTranscribe).not.toHaveBeenCalled();
  });

  test('route hydration synchronously hides stale conversation controls before SQLite resolves', async () => {
    let releaseHydration!: () => void;
    const hydrationGate = new Promise<void>((resolve) => {
      releaseHydration = resolve;
    });
    const service = {
      hydrateConversation: jest.fn(async () => {
        await hydrationGate;
        return {
          requestId: 'request-b',
          messageId: 'message-b',
          requestStatus: 'completed' as const,
          transcript: '',
          pendingProposals: [],
        };
      }),
    } as unknown as PrivateCaptureService;
    const store = createChatStore(async () => service);
    store.setState({
      activeSessionId: 'conversation-a',
      activeRequestId: 'request-a',
      activeMessageId: 'message-a',
      transcript: 'Private transcript from A',
      pendingProposalIds: ['proposal-a'],
      pendingProposals: [{
        id: 'proposal-a',
        summary: 'Private decision from A',
        kind: 'proposal',
        question: null,
        status: 'pending',
      }],
      phase: 'responded',
      error: null,
    });

    const hydration = store.getState().hydrateConversation('conversation-b');

    expect(store.getState()).toEqual(expect.objectContaining({
      activeSessionId: 'conversation-b',
      activeRequestId: null,
      activeMessageId: null,
      transcript: '',
      pendingProposalIds: [],
      pendingProposals: [],
      phase: 'processing',
    }));
    releaseHydration();
    await hydration;
  });

  test('an older slow hydration cannot overwrite a newer resumed conversation', async () => {
    let resolveA!: (value: Awaited<ReturnType<PrivateCaptureService['hydrateConversation']>>) => void;
    let resolveB!: (value: Awaited<ReturnType<PrivateCaptureService['hydrateConversation']>>) => void;
    const hydrateConversation = jest.fn((conversationId: string) =>
      new Promise<Awaited<ReturnType<PrivateCaptureService['hydrateConversation']>>>((resolve) => {
        if (conversationId === 'conversation-a') resolveA = resolve;
        else resolveB = resolve;
      }));
    const service = { hydrateConversation } as unknown as PrivateCaptureService;
    const store = createChatStore(async () => service);

    const hydrationA = store.getState().hydrateConversation('conversation-a');
    const hydrationB = store.getState().hydrateConversation('conversation-b');
    await Promise.resolve();
    await Promise.resolve();
    resolveB({
      requestId: 'request-b',
      messageId: 'message-b',
      requestStatus: 'transcript-confirmation-required',
      transcript: 'Private transcript B',
      pendingProposals: [],
    });
    await hydrationB;
    resolveA({
      requestId: 'request-a',
      messageId: 'message-a',
      requestStatus: 'completed',
      transcript: 'Private transcript A',
      pendingProposals: [{
        id: 'proposal-a',
        summary: 'Private proposal A',
        kind: 'proposal',
        question: null,
        status: 'pending',
      }],
    });
    await hydrationA;

    expect(store.getState()).toEqual(expect.objectContaining({
      activeSessionId: 'conversation-b',
      activeRequestId: 'request-b',
      activeMessageId: 'message-b',
      transcript: 'Private transcript B',
      pendingProposals: [],
      phase: 'transcript-review',
    }));
  });

  test('an older hydration failure cannot replace a newer resumed conversation with error state', async () => {
    let rejectA!: (error: Error) => void;
    const hydrateConversation = jest.fn((conversationId: string) =>
      conversationId === 'conversation-a'
        ? new Promise<Awaited<ReturnType<PrivateCaptureService['hydrateConversation']>>>(
          (_resolve, reject) => { rejectA = reject; },
        )
        : Promise.resolve({
          requestId: 'request-b',
          messageId: 'message-b',
          requestStatus: 'completed' as const,
          transcript: '',
          pendingProposals: [],
        }));
    const store = createChatStore(async () => ({
      hydrateConversation,
    } as unknown as PrivateCaptureService));

    const hydrationA = store.getState().hydrateConversation('conversation-a');
    const hydrationB = store.getState().hydrateConversation('conversation-b');
    await Promise.resolve();
    await hydrationB;
    rejectA(new Error('A failed after B opened'));
    await expect(hydrationA).rejects.toThrow('A failed after B opened');

    expect(store.getState()).toEqual(expect.objectContaining({
      activeSessionId: 'conversation-b',
      activeRequestId: 'request-b',
      activeMessageId: 'message-b',
      phase: 'responded',
      error: null,
    }));
  });

  test('a fresh thread history exposes durable pending work without loading the capture service', async () => {
    const transcribe = jest.fn(async () => ({
      transcript: 'Review me after restart',
      durationSeconds: 9,
      usage: {
        provider: 'openai' as const,
        model: 'fixture-transcription',
        audioSeconds: 9,
        estimatedCostUsd: 0.001,
      },
    }));
    const ids = [...IDS];
    const service = createPrivateCaptureService({
      database: db,
      coach: async (request) => response(request),
      transcribe,
      now: () => NOW,
      createId: () => ids.shift()!,
      getProfileId: async () => 'profile-1',
      audioFiles: {
        persistRecording: async () => 'file:///documents/taisa-audio/history-request.m4a',
        deleteRecording: async () => undefined,
      },
    });
    await service.submitVoice({
      conversationId: 'conversation-with-pending-work',
      audioUri: 'file:///cache/history-recording.m4a',
      durationSeconds: 9,
    });
    const getCaptureService = jest.fn(async () => service);
    const freshHistoryStore = createThreadStore({
      openDatabase: async () => db,
      getCaptureService,
    });

    await freshHistoryStore.getState().fetchThreads();

    expect(freshHistoryStore.getState().threads).toEqual([
      expect.objectContaining({
        id: 'conversation-with-pending-work',
        pendingRequestStatus: 'transcript-confirmation-required',
        pendingProposalCount: 0,
      }),
    ]);
    expect(getCaptureService).not.toHaveBeenCalled();
  });

  test('fresh thread history counts durable decisions that still need the user', async () => {
    const ids = [...IDS];
    const service = createPrivateCaptureService({
      database: db,
      coach: async (request) => ({
        ...response(request),
        proposals: [{
          operation: 'propose',
          candidate: {
            type: 'goal',
            statement: 'Lead the next roadmap workshop',
            provenance: 'user-confirmed',
            lifecycle: 'active',
            confidence: 'established',
            sourceMessageIds: ['provider-source-is-replaced-locally'],
            supersedesId: null,
          },
          reason: 'This is an explicit direction for future coaching.',
          requiresConfirmation: false,
        }],
      }),
      transcribe: async () => { throw new Error('not used'); },
      now: () => NOW,
      createId: () => ids.shift()!,
      getProfileId: async () => 'profile-1',
      audioFiles: {
        persistRecording: async ({ sourceUri }) => sourceUri,
        deleteRecording: async () => undefined,
      },
    });
    await service.submitText({
      conversationId: 'conversation-with-decision',
      content: 'I want to lead the next roadmap workshop.',
    });
    const getCaptureService = jest.fn(async () => service);
    const freshHistoryStore = createThreadStore({
      openDatabase: async () => db,
      getCaptureService,
    });

    await freshHistoryStore.getState().fetchThreads();

    expect(freshHistoryStore.getState().threads).toEqual([
      expect.objectContaining({
        id: 'conversation-with-decision',
        pendingRequestStatus: 'completed',
        pendingProposalCount: 1,
      }),
    ]);
    expect(getCaptureService).not.toHaveBeenCalled();
  });

  test('thread store synchronously ignores a rapid duplicate send', async () => {
    let release!: () => void;
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const submitText = jest.fn(async () => {
      await gate;
      return {};
    });
    const store = createThreadStore({
      openDatabase: async () => db,
      getCaptureService: async () => ({ submitText } as unknown as PrivateCaptureService),
    });

    const first = store.getState().sendMessage('conversation-1', 'Same tap');
    const second = store.getState().sendMessage('conversation-1', 'Same tap');
    expect(second).toBe(first);
    release();
    await Promise.all([first, second]);
    expect(submitText).toHaveBeenCalledTimes(1);
    expect(submitText).toHaveBeenCalledWith(expect.objectContaining({
      intentId: expect.any(String),
    }));
  });
});
