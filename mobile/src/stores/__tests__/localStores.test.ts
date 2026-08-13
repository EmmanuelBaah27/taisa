import type { CoachingRequest, CoachingResponse } from '@taisa/shared';

import { getProfile, listProfiles } from '../../repositories/profileRepository';
import { createTestDatabase, type TestDatabase } from '../../repositories/__tests__/testDatabase';
import { createPrivateCaptureService, type PrivateCaptureService } from '../../services/privateCapture';
import { createCareerStore } from '../careerStore';
import { canAbandonVoiceSubmission, createChatStore } from '../chatStore';
import { createThreadStore } from '../threadStore';

const NOW = '2026-08-10T09:00:00.000Z';
const IDS = [
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000002',
  '00000000-0000-4000-8000-000000000003',
  '00000000-0000-4000-8000-000000000004',
  '00000000-0000-4000-8000-000000000005',
];

interface Deferred<T> {
  promise: Promise<T>;
  resolve(value: T): void;
  reject(error: Error): void;
}

function deferred<T>(): Deferred<T> {
  let resolve!: (value: T) => void;
  let reject!: (error: Error) => void;
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, resolve, reject };
}

type ChatStoreInstance = ReturnType<typeof createChatStore>;

const HYDRATED_B = {
  preferredInputMode: 'voice' as const,
  requestId: 'request-b',
  messageId: 'message-b',
  requestKind: 'voice' as const,
  requestStatus: 'transcript-confirmation-required' as const,
  transcript: 'Private transcript B',
  pendingProposals: [{
    id: 'proposal-b',
    summary: 'Private proposal B',
    kind: 'proposal' as const,
    question: null,
    status: 'pending' as const,
  }],
};

test('a fresh local voice draft does not own a completed voice submission', async () => {
  const service = {
    hydrateConversation: jest.fn(async () => ({
      ...HYDRATED_B,
      requestStatus: 'completed' as const,
    })),
  } as unknown as PrivateCaptureService;
  const store = createChatStore(async () => service);

  await store.getState().hydrateConversation('conversation-b');
  expect(store.getState()).toMatchObject({
    activeRequestId: 'request-b',
    activeRequestKind: 'voice',
    activeRequestStatus: 'completed',
  });
  expect(canAbandonVoiceSubmission(store.getState())).toBe(false);

  expect(canAbandonVoiceSubmission({
    activeRequestId: 'failed-voice-request',
    activeRequestKind: 'voice',
    activeRequestStatus: 'transcription-failed',
  })).toBe(true);
});

test('a restored failed voice request can be abandoned to return to the composer', async () => {
  const service = {
    hydrateConversation: jest.fn(async () => ({
      ...HYDRATED_B,
      requestStatus: 'transcription-failed' as const,
      transcript: '',
    })),
    abandonVoiceSubmission: jest.fn(async () => undefined),
  } as unknown as PrivateCaptureService;
  const store = createChatStore(async () => service);

  await store.getState().hydrateConversation('conversation-b');
  expect(store.getState()).toMatchObject({
    phase: 'error',
    activeRequestKind: 'voice',
    activeRequestId: 'request-b',
  });

  await store.getState().abandonVoiceSubmission('request-b');
  expect(service.abandonVoiceSubmission).toHaveBeenCalledWith('request-b');
  expect(store.getState()).toMatchObject({
    phase: 'idle',
    activeRequestKind: null,
    activeRequestId: null,
    preferredInputMode: 'voice',
  });
});

test('hydrates and durably switches the conversation input mode', async () => {
  const service = {
    hydrateConversation: jest.fn(async () => ({
      ...HYDRATED_B,
      preferredInputMode: 'voice' as const,
    })),
    setPreferredInputMode: jest.fn(async () => undefined),
  } as unknown as PrivateCaptureService;
  const store = createChatStore(async () => service);

  await store.getState().hydrateConversation('conversation-b');
  expect(store.getState().preferredInputMode).toBe('voice');

  await store.getState().setPreferredInputMode('conversation-b', 'text');
  expect(service.setPreferredInputMode).toHaveBeenCalledWith(expect.objectContaining({
    conversationId: 'conversation-b',
    preferredInputMode: 'text',
    idempotencyId: expect.any(String),
  }));
  expect(store.getState().preferredInputMode).toBe('text');
});

const COMPLETED_A = {
  status: 'completed' as const,
  requestId: 'request-a-result',
  messageId: 'message-a-result',
  assistantMessageId: 'assistant-a-result',
  pendingProposalIds: ['proposal-a-result'],
  pendingProposals: [{
    id: 'proposal-a-result',
    summary: 'Private proposal A result',
    kind: 'proposal' as const,
    question: null,
    status: 'pending' as const,
  }],
};

const CHAT_OPERATION_CASES: Array<{
  name: string;
  serviceMethod: keyof PrivateCaptureService;
  result: unknown;
  start(store: ChatStoreInstance): Promise<void>;
}> = [
  {
    name: 'hydration',
    serviceMethod: 'hydrateConversation',
    result: { ...HYDRATED_B, requestId: 'request-a-result', messageId: 'message-a-result' },
    start: (store) => store.getState().hydrateConversation('conversation-a'),
  },
  {
    name: 'private save',
    serviceMethod: 'savePrivateDraft',
    result: { status: 'private', conversationId: 'conversation-a', messageId: 'message-a-result' },
    start: (store) => store.getState().savePrivateDraft('conversation-a', 'Private A'),
  },
  {
    name: 'text submit',
    serviceMethod: 'submitText',
    result: COMPLETED_A,
    start: (store) => store.getState().submitText('conversation-a', 'Submitted A'),
  },
  {
    name: 'voice submit',
    serviceMethod: 'submitVoice',
    result: {
      status: 'transcript-confirmation-required',
      requestId: 'request-a-result',
      messageId: 'message-a-result',
      transcript: 'Private transcript A result',
    },
    start: (store) => store.getState().submitVoice('conversation-a', 'file:///a.m4a', 4),
  },
  {
    name: 'transcript edit',
    serviceMethod: 'updateTranscript',
    result: undefined,
    start: (store) => store.getState().updateTranscript('Edited private transcript A'),
  },
  {
    name: 'transcript confirmation',
    serviceMethod: 'confirmTranscript',
    result: COMPLETED_A,
    start: (store) => store.getState().confirmTranscript(),
  },
  {
    name: 'submission retry',
    serviceMethod: 'retrySubmission',
    result: COMPLETED_A,
    start: (store) => store.getState().retrySubmission(),
  },
  {
    name: 'proposal confirmation',
    serviceMethod: 'confirmProposal',
    result: undefined,
    start: (store) => store.getState().confirmProposal('proposal-a'),
  },
  {
    name: 'clarification resolution',
    serviceMethod: 'resolveClarification',
    result: undefined,
    start: (store) => store.getState().resolveClarification('proposal-a', 'coexist'),
  },
  {
    name: 'recording discard cleanup',
    serviceMethod: 'discardRecording',
    result: undefined,
    start: (store) => store.getState().discardRecording('file:///a.m4a'),
  },
  {
    name: 'voice submission cleanup',
    serviceMethod: 'abandonVoiceSubmission',
    result: undefined,
    start: (store) => store.getState().abandonVoiceSubmission('request-a'),
  },
  {
    name: 'queued audio cleanup',
    serviceMethod: 'drainAudioCleanupQueue',
    result: undefined,
    start: (store) => store.getState().drainAudioCleanupQueue(),
  },
];

function seedConversationA(store: ChatStoreInstance): void {
  store.setState({
    activeSessionId: 'conversation-a',
    activeRequestId: 'request-a',
    activeMessageId: 'message-a',
    transcript: 'Private transcript A',
    pendingProposalIds: ['proposal-a'],
    pendingProposals: [{
      id: 'proposal-a',
      summary: 'Private proposal A',
      kind: 'clarification',
      question: 'What should happen to the older direction?',
      status: 'pending',
    }],
    phase: 'transcript-review',
    isBusy: false,
    error: null,
  });
}

function visibleChatState(store: ChatStoreInstance) {
  const state = store.getState();
  return {
    activeSessionId: state.activeSessionId,
    activeRequestId: state.activeRequestId,
    activeMessageId: state.activeMessageId,
    transcript: state.transcript,
    pendingProposalIds: state.pendingProposalIds,
    pendingProposals: state.pendingProposals,
    phase: state.phase,
    isBusy: state.isBusy,
    error: state.error,
  };
}

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
        setItemAsync: async (_key: string, value: string) => { secureUserId = value; },
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

    expect(secureUserId).toBeNull();
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

  test('discovers the sole restored profile instead of using a new installation identity', async () => {
    let mutation = 0;
    const dependencies = {
      openDatabase: async () => db,
      secureStore: {
        getItemAsync: async () => secureUserId,
        setItemAsync: async (_key: string, value: string) => { secureUserId = value; },
      },
      now: () => NOW,
      createId: () => `restored-profile-mutation-${mutation += 1}`,
    };
    const original = createCareerStore(dependencies);
    await original.getState().initUser('restored-profile', { currentRole: 'Restored role' });

    secureUserId = 'new-installation-rate-limit-id';
    const afterRestore = createCareerStore(dependencies);
    await expect(afterRestore.getState().fetchProfile()).resolves.toBeUndefined();

    expect(afterRestore.getState()).toEqual(expect.objectContaining({
      userId: 'restored-profile',
      profile: expect.objectContaining({ id: 'restored-profile', currentRole: 'Restored role' }),
    }));
    expect(await listProfiles(db)).toHaveLength(1);
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

  test('a fresh chat store restores the completed voice request without provider calls', async () => {
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

    await beforeRestartStore.getState().setPreferredInputMode(
      'conversation-after-process-death',
      'voice',
    );
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
      preferredInputMode: 'voice',
      transcript: 'A transcript that survives process death',
      phase: 'responded',
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
      preferredInputMode: 'voice',
      requestId: 'request-b',
      messageId: 'message-b',
      requestKind: 'voice',
      requestStatus: 'transcript-confirmation-required',
      transcript: 'Private transcript B',
      pendingProposals: [],
    });
    await hydrationB;
    resolveA({
      preferredInputMode: 'text',
      requestId: 'request-a',
      messageId: 'message-a',
      requestKind: 'text',
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
      preferredInputMode: 'voice',
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

  describe.each(CHAT_OPERATION_CASES)('$name conversation ownership', (operation) => {
    function createDeferredOperationService(operationResult: Deferred<unknown>) {
      const service = {
        savePrivateDraft: jest.fn(async () => ({
          status: 'private' as const,
          conversationId: 'unused',
          messageId: 'unused',
        })),
        submitText: jest.fn(async () => COMPLETED_A),
        submitVoice: jest.fn(async () => ({
          status: 'transcript-confirmation-required' as const,
          requestId: 'unused',
          messageId: 'unused',
          transcript: 'unused',
        })),
        submitVoiceAndCoach: jest.fn(async () => COMPLETED_A),
        updateTranscript: jest.fn(async () => undefined),
        confirmTranscript: jest.fn(async () => COMPLETED_A),
        retrySubmission: jest.fn(async () => COMPLETED_A),
        confirmProposal: jest.fn(async () => undefined),
        resolveClarification: jest.fn(async () => undefined),
        hydrateConversation: jest.fn(async (_conversationId: string) => HYDRATED_B),
        drainAudioCleanupQueue: jest.fn(async () => undefined),
        discardRecording: jest.fn(async () => undefined),
        abandonVoiceSubmission: jest.fn(async () => undefined),
      };
      const mutableService = service as unknown as Record<string, unknown>;
      if (operation.serviceMethod === 'hydrateConversation') {
        service.hydrateConversation.mockImplementation(async (conversationId: string) => (
          conversationId === 'conversation-a'
            ? operationResult.promise as Promise<typeof HYDRATED_B>
            : HYDRATED_B
        ));
      } else {
        mutableService[operation.serviceMethod] = jest.fn(() => operationResult.promise);
      }
      return service as unknown as PrivateCaptureService;
    }

    it.each(['completes', 'fails'] as const)(
      'cannot change resumed B when A %s later',
      async (outcome) => {
        const operationResult = deferred<unknown>();
        const store = createChatStore(async () => createDeferredOperationService(operationResult));
        seedConversationA(store);

        const aOperation = operation.start(store);
        const observedAOperation = aOperation.then(
          () => undefined,
          () => undefined,
        );
        await Promise.resolve();
        await store.getState().hydrateConversation('conversation-b');

        if (outcome === 'completes') operationResult.resolve(operation.result);
        else operationResult.reject(new Error('A finished after B opened'));
        await observedAOperation;

        expect(visibleChatState(store)).toEqual({
          activeSessionId: 'conversation-b',
          activeRequestId: 'request-b',
          activeMessageId: 'message-b',
          transcript: 'Private transcript B',
          pendingProposalIds: ['proposal-b'],
          pendingProposals: HYDRATED_B.pendingProposals,
          phase: 'transcript-review',
          isBusy: false,
          error: null,
        });
      },
    );

    it.each(['completes', 'fails'] as const)(
      'cannot repopulate cleared state when A %s later',
      async (outcome) => {
        const operationResult = deferred<unknown>();
        const store = createChatStore(async () => createDeferredOperationService(operationResult));
        seedConversationA(store);

        const aOperation = operation.start(store);
        const observedAOperation = aOperation.then(
          () => undefined,
          () => undefined,
        );
        await Promise.resolve();
        store.getState().clearActiveSession();

        if (outcome === 'completes') operationResult.resolve(operation.result);
        else operationResult.reject(new Error('A finished after the chat closed'));
        await observedAOperation;

        expect(visibleChatState(store)).toEqual({
          activeSessionId: null,
          activeRequestId: null,
          activeMessageId: null,
          transcript: '',
          pendingProposalIds: [],
          pendingProposals: [],
          phase: 'idle',
          isBusy: false,
          error: null,
        });
      },
    );
  });

  test('an older in-flight action releases without deduplicating or clearing B busy state', async () => {
    const submitA = deferred<typeof COMPLETED_A>();
    const submitB = deferred<typeof COMPLETED_A>();
    const submitText = jest.fn((input: { conversationId: string }) => (
      input.conversationId === 'conversation-a' ? submitA.promise : submitB.promise
    ));
    const service = {
      submitText,
      hydrateConversation: jest.fn(async () => HYDRATED_B),
    } as unknown as PrivateCaptureService;
    const store = createChatStore(async () => service);
    seedConversationA(store);

    const operationA = store.getState().submitText('conversation-a', 'A thought');
    await Promise.resolve();
    await store.getState().hydrateConversation('conversation-b');
    const operationB = store.getState().submitText('conversation-b', 'B thought');
    await Promise.resolve();

    expect(submitText).toHaveBeenCalledTimes(2);
    expect(store.getState().isBusy).toBe(true);
    submitA.resolve(COMPLETED_A);
    await operationA;
    expect(store.getState().isBusy).toBe(true);

    submitB.resolve({
      ...COMPLETED_A,
      requestId: 'request-b-result',
      messageId: 'message-b-result',
    });
    await operationB;
    expect(store.getState()).toEqual(expect.objectContaining({
      activeSessionId: 'conversation-b',
      activeRequestId: 'request-b-result',
      activeMessageId: 'message-b-result',
      phase: 'responded',
      isBusy: false,
      error: null,
    }));
  });

  test('an older request in the same conversation cannot own a replacement request or its lock', async () => {
    const confirmA = deferred<typeof COMPLETED_A>();
    const confirmReplacement = deferred<typeof COMPLETED_A>();
    const confirmTranscript = jest.fn(({ requestId }: { requestId: string }) => (
      requestId === 'request-a' ? confirmA.promise : confirmReplacement.promise
    ));
    const service = { confirmTranscript } as unknown as PrivateCaptureService;
    const store = createChatStore(async () => service);
    seedConversationA(store);

    const operationA = store.getState().confirmTranscript();
    await Promise.resolve();
    store.setState({
      activeRequestId: 'request-replacement',
      activeMessageId: 'message-replacement',
      transcript: 'Replacement transcript',
      pendingProposalIds: [],
      pendingProposals: [],
      phase: 'transcript-review',
      isBusy: false,
      error: null,
    });
    const replacementOperation = store.getState().confirmTranscript();
    await Promise.resolve();

    expect(confirmTranscript).toHaveBeenCalledTimes(2);
    confirmA.resolve(COMPLETED_A);
    await operationA;
    expect(store.getState()).toEqual(expect.objectContaining({
      activeRequestId: 'request-replacement',
      activeMessageId: 'message-replacement',
      transcript: 'Replacement transcript',
      phase: 'processing',
      isBusy: true,
    }));

    confirmReplacement.resolve({
      ...COMPLETED_A,
      requestId: 'request-replacement',
      messageId: 'message-replacement-result',
    });
    await replacementOperation;
    expect(store.getState()).toEqual(expect.objectContaining({
      activeRequestId: 'request-replacement',
      activeMessageId: 'message-replacement-result',
      phase: 'responded',
      isBusy: false,
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

  test('an older thread fetch success cannot overwrite a newer requested conversation', async () => {
    await capture.savePrivateDraft({ conversationId: 'conversation-a', content: 'Private A' });
    await capture.savePrivateDraft({ conversationId: 'conversation-b', content: 'Private B' });
    const firstOpen = deferred<TestDatabase>();
    let openCount = 0;
    const store = createThreadStore({
      openDatabase: () => {
        openCount += 1;
        return openCount === 1 ? firstOpen.promise : Promise.resolve(db);
      },
      getCaptureService: async () => capture,
    });

    const fetchA = store.getState().fetchThread('conversation-a');
    await store.getState().fetchThread('conversation-b');
    firstOpen.resolve(db);
    await fetchA;

    expect(store.getState()).toEqual(expect.objectContaining({
      currentSession: expect.objectContaining({ id: 'conversation-b' }),
      currentMessages: [expect.objectContaining({ content: 'Private B' })],
      isLoadingMessages: false,
      error: null,
    }));
  });

  test('an older thread fetch failure cannot replace a newer conversation error state', async () => {
    await capture.savePrivateDraft({ conversationId: 'conversation-b', content: 'Private B' });
    const firstOpen = deferred<TestDatabase>();
    let openCount = 0;
    const store = createThreadStore({
      openDatabase: () => {
        openCount += 1;
        return openCount === 1 ? firstOpen.promise : Promise.resolve(db);
      },
      getCaptureService: async () => capture,
    });

    const fetchA = store.getState().fetchThread('conversation-a');
    await store.getState().fetchThread('conversation-b');
    firstOpen.reject(new Error('A failed after B opened'));
    await fetchA;

    expect(store.getState()).toEqual(expect.objectContaining({
      currentSession: expect.objectContaining({ id: 'conversation-b' }),
      currentMessages: [expect.objectContaining({ content: 'Private B' })],
      isLoadingMessages: false,
      error: null,
    }));
  });

  test('a cleared thread cannot be repopulated by an older fetch', async () => {
    await capture.savePrivateDraft({ conversationId: 'conversation-a', content: 'Private A' });
    const firstOpen = deferred<TestDatabase>();
    const store = createThreadStore({
      openDatabase: () => firstOpen.promise,
      getCaptureService: async () => capture,
    });

    const fetchA = store.getState().fetchThread('conversation-a');
    store.getState().clearThread('conversation-a');
    firstOpen.resolve(db);
    await fetchA;

    expect(store.getState()).toEqual(expect.objectContaining({
      currentSession: null,
      currentMessages: [],
      isLoadingMessages: false,
      error: null,
    }));
  });

  test('requesting B synchronously hides A and a B failure never exposes A again', async () => {
    await capture.savePrivateDraft({ conversationId: 'conversation-a', content: 'Private A' });
    await capture.savePrivateDraft({ conversationId: 'conversation-b', content: 'Private B' });
    const bOpen = deferred<TestDatabase>();
    let openCount = 0;
    const store = createThreadStore({
      openDatabase: () => {
        openCount += 1;
        return openCount === 1 ? Promise.resolve(db) : bOpen.promise;
      },
      getCaptureService: async () => capture,
    });
    await store.getState().fetchThread('conversation-a');

    const fetchB = store.getState().fetchThread('conversation-b');
    expect(store.getState()).toEqual(expect.objectContaining({
      currentSession: null,
      currentMessages: [],
      isLoadingMessages: true,
      error: null,
    }));

    bOpen.reject(new Error('B is unavailable'));
    await fetchB;
    expect(store.getState()).toEqual(expect.objectContaining({
      currentSession: null,
      currentMessages: [],
      isLoadingMessages: false,
      error: 'The local conversation is unavailable.',
    }));
  });

  test('cleanup from an older A screen cannot erase the newer B detail view', async () => {
    await capture.savePrivateDraft({ conversationId: 'conversation-a', content: 'Private A' });
    await capture.savePrivateDraft({ conversationId: 'conversation-b', content: 'Private B' });
    const store = createThreadStore({
      openDatabase: async () => db,
      getCaptureService: async () => capture,
    });
    await store.getState().fetchThread('conversation-a');
    await store.getState().fetchThread('conversation-b');

    store.getState().clearThread('conversation-a');

    expect(store.getState()).toEqual(expect.objectContaining({
      currentSession: expect.objectContaining({ id: 'conversation-b' }),
      currentMessages: [expect.objectContaining({ content: 'Private B' })],
      isLoadingMessages: false,
      error: null,
    }));
  });
});
