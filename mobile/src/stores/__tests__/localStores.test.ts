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
    const fake = {
      submitText,
      hydrateConversation,
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
