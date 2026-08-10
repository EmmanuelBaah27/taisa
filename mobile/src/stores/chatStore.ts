import * as Crypto from 'expo-crypto';
import { create } from 'zustand';

import { getPrivateCaptureService } from '../services/localPlatform';
import type {
  ClarificationChoice,
  PendingProposal,
  PrivateCaptureService,
} from '../services/privateCapture';

export type ChatPhase =
  | 'idle'
  | 'listening'
  | 'recording-ready'
  | 'transcribing'
  | 'transcript-review'
  | 'processing'
  | 'responded'
  | 'error';

interface ChatStore {
  activeSessionId: string | null;
  activeRequestId: string | null;
  activeMessageId: string | null;
  transcript: string;
  pendingProposalIds: string[];
  pendingProposals: PendingProposal[];
  phase: ChatPhase;
  isBusy: boolean;
  error: string | null;
  setActiveSessionId: (id: string) => void;
  setPhase: (phase: ChatPhase) => void;
  hydrateConversation: (conversationId: string) => Promise<void>;
  savePrivateDraft: (conversationId: string, content: string) => Promise<void>;
  submitText: (conversationId: string, content: string) => Promise<void>;
  submitVoice: (
    conversationId: string,
    audioUri: string,
    durationSeconds: number,
  ) => Promise<void>;
  updateTranscript: (transcript: string) => Promise<void>;
  confirmTranscript: () => Promise<void>;
  retrySubmission: () => Promise<void>;
  confirmProposal: (confirmationId: string) => Promise<void>;
  resolveClarification: (
    confirmationId: string,
    choice: ClarificationChoice,
  ) => Promise<void>;
  discardRecording: (uri: string) => Promise<void>;
  abandonVoiceSubmission: (requestId: string) => Promise<void>;
  clearActiveSession: () => void;
  clearError: () => void;
}

type CaptureServiceProvider = () => Promise<PrivateCaptureService>;

function safeError(error: unknown): string {
  return error instanceof Error &&
    (error.name === 'SubmissionFailedError' || error.name === 'SubmissionValidationError')
    ? error.message
    : 'Taisa could not complete this action. Your content remains on this device.';
}

export function createChatStore(
  getCaptureService: CaptureServiceProvider = getPrivateCaptureService,
) {
  let inFlight: Promise<void> | null = null;
  let localIntentSequence = 0;
  function createLocalIntentId(): string {
    const generated = Crypto.randomUUID();
    return typeof generated === 'string' && generated.length > 0
      ? generated
      : `local-chat-intent-${localIntentSequence += 1}`;
  }
  return create<ChatStore>((set, get) => {
    function guarded(operation: () => Promise<void>): Promise<void> {
      if (inFlight !== null) return inFlight;
      set({ isBusy: true });
      const promise = operation().finally(() => {
        if (inFlight === promise) {
          inFlight = null;
          set({ isBusy: false });
        }
      });
      inFlight = promise;
      return promise;
    }

    return ({
    activeSessionId: null,
    activeRequestId: null,
    activeMessageId: null,
    transcript: '',
    pendingProposalIds: [],
    pendingProposals: [],
    phase: 'idle',
    isBusy: false,
    error: null,
    setActiveSessionId: (id) => set({ activeSessionId: id }),
    setPhase: (phase) => set({ phase }),

    hydrateConversation: async (conversationId) => {
      const service = await getCaptureService();
      const restored = await service.hydrateConversation(conversationId);
      const phase: ChatPhase = restored.requestStatus === 'transcript-confirmation-required'
        ? 'transcript-review'
        : restored.requestStatus === 'completed'
          ? 'responded'
          : restored.requestStatus === null
            ? 'idle'
            : 'error';
      set({
        activeSessionId: conversationId,
        activeRequestId: restored.requestId,
        activeMessageId: restored.messageId,
        transcript: restored.transcript,
        pendingProposalIds: restored.pendingProposals.map((proposal) => proposal.id),
        pendingProposals: restored.pendingProposals,
        phase,
        error: phase === 'error'
          ? 'This submission was interrupted. Your content remains on this device and can be retried.'
          : null,
      });
    },

    savePrivateDraft: async (conversationId, content) => {
      try {
        const service = await getCaptureService();
        const result = await service.savePrivateDraft({ conversationId, content });
        set({ activeSessionId: conversationId, activeMessageId: result.messageId, error: null });
      } catch (error) {
        set({ phase: 'error', error: safeError(error) });
        throw error;
      }
    },

    submitText: (conversationId, content) => guarded(async () => {
      set({ phase: 'processing', error: null, activeSessionId: conversationId });
      try {
        const service = await getCaptureService();
        const result = await service.submitText({
          conversationId,
          content,
          intentId: createLocalIntentId(),
        });
        set({
          activeRequestId: result.requestId,
          activeMessageId: result.messageId,
          pendingProposalIds: result.pendingProposalIds,
          pendingProposals: result.pendingProposals,
          phase: 'responded',
        });
      } catch (error) {
        const requestId = typeof error === 'object' && error !== null && 'requestId' in error
          ? String(error.requestId)
          : null;
        set({ activeRequestId: requestId, phase: 'error', error: safeError(error) });
        throw error;
      }
    }),

    submitVoice: (conversationId, audioUri, durationSeconds) => guarded(async () => {
      set({ phase: 'transcribing', error: null, activeSessionId: conversationId });
      try {
        const service = await getCaptureService();
        const result = await service.submitVoice({
          conversationId,
          audioUri,
          durationSeconds,
          intentId: createLocalIntentId(),
        });
        set({
          activeRequestId: result.requestId,
          activeMessageId: result.messageId,
          transcript: result.transcript,
          phase: 'transcript-review',
        });
      } catch (error) {
        const requestId = typeof error === 'object' && error !== null && 'requestId' in error
          ? String(error.requestId)
          : null;
        set({ activeRequestId: requestId, phase: 'error', error: safeError(error) });
        throw error;
      }
    }),

    updateTranscript: async (transcript) => {
      const requestId = get().activeRequestId;
      if (requestId === null) throw new Error('No transcript is active');
      const service = await getCaptureService();
      await service.updateTranscript({ requestId, transcript });
      set({ transcript });
    },

    confirmTranscript: () => guarded(async () => {
      const requestId = get().activeRequestId;
      if (requestId === null) throw new Error('No transcript is active');
      set({ phase: 'processing', error: null });
      try {
        const service = await getCaptureService();
        const result = await service.confirmTranscript({ requestId });
        set({
          activeMessageId: result.messageId,
          pendingProposalIds: result.pendingProposalIds,
          pendingProposals: result.pendingProposals,
          phase: 'responded',
        });
      } catch (error) {
        set({
          phase: error instanceof Error && error.name === 'SubmissionValidationError'
            ? 'transcript-review'
            : 'error',
          error: safeError(error),
        });
        throw error;
      }
    }),

    retrySubmission: () => guarded(async () => {
      const requestId = get().activeRequestId;
      if (requestId === null) throw new Error('No failed submission is active');
      set({ phase: 'processing', error: null });
      try {
        const service = await getCaptureService();
        const result = await service.retrySubmission(requestId);
        if (result.status === 'transcript-confirmation-required') {
          set({ transcript: result.transcript, phase: 'transcript-review' });
        } else {
          set({
            activeMessageId: result.messageId,
            pendingProposalIds: result.pendingProposalIds,
            pendingProposals: result.pendingProposals,
            phase: 'responded',
          });
        }
      } catch (error) {
        set({ phase: 'error', error: safeError(error) });
        throw error;
      }
    }),

    confirmProposal: (confirmationId) => guarded(async () => {
      const service = await getCaptureService();
      await service.confirmProposal({
        confirmationId,
        localUserActionId: createLocalIntentId(),
        actedAt: new Date().toISOString(),
      });
      set((state) => ({
        pendingProposalIds: state.pendingProposalIds.filter((id) => id !== confirmationId),
        pendingProposals: state.pendingProposals.filter((proposal) => proposal.id !== confirmationId),
      }));
    }),

    resolveClarification: (confirmationId, choice) => guarded(async () => {
      const service = await getCaptureService();
      await service.resolveClarification({
        confirmationId,
        choice,
        localUserActionId: createLocalIntentId(),
        actedAt: new Date().toISOString(),
      });
      set((state) => ({
        pendingProposalIds: state.pendingProposalIds.filter((id) => id !== confirmationId),
        pendingProposals: state.pendingProposals.filter((proposal) => proposal.id !== confirmationId),
      }));
    }),

    discardRecording: async (uri) => {
      const service = await getCaptureService();
      await service.discardRecording(uri);
    },

    abandonVoiceSubmission: async (requestId) => {
      const service = await getCaptureService();
      await service.abandonVoiceSubmission(requestId);
      set({
        activeRequestId: null,
        activeMessageId: null,
        transcript: '',
        phase: 'idle',
        error: null,
      });
    },

    clearActiveSession: () => set({
      activeSessionId: null,
      activeRequestId: null,
      activeMessageId: null,
      transcript: '',
      pendingProposalIds: [],
      pendingProposals: [],
      phase: 'idle',
      isBusy: false,
      error: null,
    }),
    clearError: () => set({ error: null }),
    });
  });
}

export const useChatStore = createChatStore();
