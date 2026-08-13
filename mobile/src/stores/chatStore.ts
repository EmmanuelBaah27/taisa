import * as Crypto from 'expo-crypto';
import { create } from 'zustand';
import type { PreferredInputMode } from '@taisa/shared';

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
  activeRequestKind: 'text' | 'voice' | null;
  activeMessageId: string | null;
  preferredInputMode: PreferredInputMode;
  transcript: string;
  pendingProposalIds: string[];
  pendingProposals: PendingProposal[];
  phase: ChatPhase;
  isBusy: boolean;
  error: string | null;
  setActiveSessionId: (id: string) => void;
  setPhase: (phase: ChatPhase) => void;
  drainAudioCleanupQueue: () => Promise<void>;
  hydrateConversation: (conversationId: string) => Promise<void>;
  setPreferredInputMode: (
    conversationId: string,
    preferredInputMode: PreferredInputMode,
  ) => Promise<void>;
  savePrivateDraft: (conversationId: string, content: string) => Promise<void>;
  submitText: (conversationId: string, content: string) => Promise<void>;
  submitVoice: (
    conversationId: string,
    audioUri: string,
    durationSeconds: number,
    typedClarification?: string,
  ) => Promise<void>;
  updateTranscript: (transcript: string) => Promise<void>;
  confirmTranscript: () => Promise<void>;
  reviseTranscript: (transcript: string) => Promise<void>;
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

interface ConversationOwnership {
  generation: number;
  conversationId: string | null;
  requestId?: string | null;
}

function safeError(error: unknown): string {
  return error instanceof Error &&
    (error.name === 'SubmissionFailedError' || error.name === 'SubmissionValidationError')
    ? error.message
    : 'Taisa could not complete this action. Your content remains on this device.';
}

export function createChatStore(
  getCaptureService: CaptureServiceProvider = getPrivateCaptureService,
) {
  let inFlight: { ownership: ConversationOwnership; promise: Promise<void> } | null = null;
  let localIntentSequence = 0;
  function createLocalIntentId(): string {
    const generated = Crypto.randomUUID();
    return typeof generated === 'string' && generated.length > 0
      ? generated
      : `local-chat-intent-${localIntentSequence += 1}`;
  }
  return create<ChatStore>((set, get) => {
    let conversationGeneration = 0;

    function isCurrent(ownership: ConversationOwnership): boolean {
      const state = get();
      return ownership.generation === conversationGeneration &&
        ownership.conversationId === state.activeSessionId &&
        (ownership.requestId === undefined || ownership.requestId === state.activeRequestId);
    }

    function captureOwnership(requestId?: string | null): ConversationOwnership {
      return {
        generation: conversationGeneration,
        conversationId: get().activeSessionId,
        ...(requestId === undefined ? {} : { requestId }),
      };
    }

    function activateConversation(
      conversationId: string,
      options: { forceNewGeneration?: boolean; resetBusy?: boolean } = {},
    ): ConversationOwnership {
      const changed = get().activeSessionId !== conversationId;
      if (changed || options.forceNewGeneration === true) conversationGeneration += 1;
      if (changed || options.resetBusy === true) {
        set({
          activeSessionId: conversationId,
          isBusy: false,
        });
      }
      return captureOwnership();
    }

    function setIfCurrent(
      ownership: ConversationOwnership,
      update: Partial<ChatStore> | ((state: ChatStore) => Partial<ChatStore>),
    ): boolean {
      if (!isCurrent(ownership)) return false;
      set(update);
      return true;
    }

    function guarded(
      ownership: ConversationOwnership,
      operation: () => Promise<void>,
    ): Promise<void> {
      if (
        inFlight !== null &&
        inFlight.ownership.generation === ownership.generation &&
        inFlight.ownership.conversationId === ownership.conversationId &&
        inFlight.ownership.requestId === ownership.requestId
      ) return inFlight.promise;
      if (isCurrent(ownership)) set({ isBusy: true });
      const promise = operation().finally(() => {
        if (inFlight?.promise === promise) {
          inFlight = null;
        }
        if (isCurrent(ownership)) set({ isBusy: false });
      });
      inFlight = { ownership, promise };
      return promise;
    }

    return ({
    activeSessionId: null,
    activeRequestId: null,
    activeRequestKind: null,
    activeMessageId: null,
    preferredInputMode: 'text',
    transcript: '',
    pendingProposalIds: [],
    pendingProposals: [],
    phase: 'idle',
    isBusy: false,
    error: null,
    setActiveSessionId: (id) => {
      activateConversation(id);
    },
    setPhase: (phase) => set({ phase }),

    drainAudioCleanupQueue: async () => {
      const ownership = captureOwnership();
      const service = await getCaptureService();
      await service.drainAudioCleanupQueue();
      // Cleanup is durable service work. Capturing ownership prevents future UI
      // callbacks from being added here without the same conversation boundary.
      void isCurrent(ownership);
    },

    hydrateConversation: async (conversationId) => {
      const ownership = activateConversation(conversationId, {
        forceNewGeneration: true,
        resetBusy: true,
      });
      setIfCurrent(ownership, {
        activeSessionId: conversationId,
        activeRequestId: null,
        activeRequestKind: null,
        activeMessageId: null,
        preferredInputMode: 'text',
        transcript: '',
        pendingProposalIds: [],
        pendingProposals: [],
        phase: 'processing',
        isBusy: false,
        error: null,
      });
      try {
        const service = await getCaptureService();
        const restored = await service.hydrateConversation(conversationId);
        const phase: ChatPhase = restored.requestStatus === 'transcript-confirmation-required'
          ? 'transcript-review'
          : restored.requestStatus === 'completed'
            ? 'responded'
            : restored.requestStatus === null
              ? 'idle'
              : 'error';
        setIfCurrent(ownership, {
          activeSessionId: conversationId,
          activeRequestId: restored.requestId,
          activeRequestKind: restored.requestKind,
          activeMessageId: restored.messageId,
          preferredInputMode: restored.preferredInputMode,
          transcript: restored.transcript,
          pendingProposalIds: restored.pendingProposals.map((proposal) => proposal.id),
          pendingProposals: restored.pendingProposals,
          phase,
          error: phase === 'error'
            ? 'This submission was interrupted. Your content remains on this device and can be retried.'
            : null,
        });
      } catch (hydrateError) {
        setIfCurrent(ownership, {
          activeSessionId: conversationId,
          activeRequestId: null,
          activeRequestKind: null,
          activeMessageId: null,
          transcript: '',
          pendingProposalIds: [],
          pendingProposals: [],
          phase: 'error',
          error: 'The local conversation could not be restored.',
        });
        throw hydrateError;
      }
    },

    setPreferredInputMode: async (conversationId, preferredInputMode) => {
      const ownership = activateConversation(conversationId);
      setIfCurrent(ownership, { preferredInputMode });
      const service = await getCaptureService();
      await service.setPreferredInputMode({
        conversationId,
        preferredInputMode,
        idempotencyId: createLocalIntentId(),
      });
    },

    savePrivateDraft: async (conversationId, content) => {
      const ownership = activateConversation(conversationId);
      try {
        const service = await getCaptureService();
        const result = await service.savePrivateDraft({ conversationId, content });
        setIfCurrent(ownership, {
          activeSessionId: conversationId,
          activeRequestKind: 'text',
          activeMessageId: result.messageId,
          error: null,
        });
      } catch (error) {
        setIfCurrent(ownership, { phase: 'error', error: safeError(error) });
        throw error;
      }
    },

    submitText: (conversationId, content) => {
      const ownership = activateConversation(conversationId);
      return guarded(ownership, async () => {
        setIfCurrent(ownership, {
          phase: 'processing',
          error: null,
          activeSessionId: conversationId,
          activeRequestKind: 'text',
        });
        try {
          const service = await getCaptureService();
          const result = await service.submitText({
            conversationId,
            content,
            intentId: createLocalIntentId(),
          });
          setIfCurrent(ownership, {
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
          setIfCurrent(ownership, {
            activeRequestId: requestId,
            phase: 'error',
            error: safeError(error),
          });
          throw error;
        }
      });
    },

    submitVoice: (conversationId, audioUri, durationSeconds, typedClarification) => {
      const ownership = activateConversation(conversationId);
      return guarded(ownership, async () => {
        setIfCurrent(ownership, {
          phase: 'transcribing',
          error: null,
          activeSessionId: conversationId,
          activeRequestKind: 'voice',
        });
        try {
          const service = await getCaptureService();
          const confirmation = await service.submitVoice({
            conversationId,
            audioUri,
            durationSeconds,
            preferredInputMode: get().preferredInputMode,
            intentId: createLocalIntentId(),
          });
          const clarification = typedClarification?.trim() ?? '';
          const submittedTranscript = clarification.length > 0
            ? `${confirmation.transcript}\n\n${clarification}`
            : confirmation.transcript;
          if (clarification.length > 0) {
            await service.updateTranscript({
              requestId: confirmation.requestId,
              transcript: submittedTranscript,
            });
          }
          setIfCurrent(ownership, {
            activeRequestId: confirmation.requestId,
            activeMessageId: confirmation.messageId,
            transcript: submittedTranscript,
            phase: 'processing',
          });
          const result = await service.confirmTranscript({ requestId: confirmation.requestId });
          setIfCurrent(ownership, {
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
          setIfCurrent(ownership, {
            activeRequestId: requestId,
            phase: 'error',
            error: safeError(error),
          });
          throw error;
        }
      });
    },

    updateTranscript: async (transcript) => {
      const requestId = get().activeRequestId;
      if (requestId === null) throw new Error('No transcript is active');
      const ownership = captureOwnership(requestId);
      const service = await getCaptureService();
      await service.updateTranscript({ requestId, transcript });
      setIfCurrent(ownership, { transcript });
    },

    confirmTranscript: () => {
      const requestId = get().activeRequestId;
      if (requestId === null) throw new Error('No transcript is active');
      const ownership = captureOwnership(requestId);
      return guarded(ownership, async () => {
        setIfCurrent(ownership, { phase: 'processing', error: null });
        try {
          const service = await getCaptureService();
          const result = await service.confirmTranscript({ requestId });
          setIfCurrent(ownership, {
            activeMessageId: result.messageId,
            pendingProposalIds: result.pendingProposalIds,
            pendingProposals: result.pendingProposals,
            phase: 'responded',
          });
        } catch (error) {
          setIfCurrent(ownership, {
            phase: error instanceof Error && error.name === 'SubmissionValidationError'
              ? 'transcript-review'
              : 'error',
            error: safeError(error),
          });
          throw error;
        }
      });
    },

    reviseTranscript: (transcript) => {
      const requestId = get().activeRequestId;
      if (requestId === null || get().activeRequestKind !== 'voice') {
        return Promise.reject(new Error('No completed voice transcript is active'));
      }
      const ownership = captureOwnership(requestId);
      return guarded(ownership, async () => {
        setIfCurrent(ownership, { phase: 'processing', error: null });
        try {
          const service = await getCaptureService();
          const result = await service.reviseSubmittedTranscript({ requestId, transcript });
          setIfCurrent(ownership, {
            activeMessageId: result.messageId,
            pendingProposalIds: result.pendingProposalIds,
            pendingProposals: result.pendingProposals,
            transcript,
            phase: 'responded',
          });
        } catch (error) {
          setIfCurrent(ownership, { phase: 'error', error: safeError(error) });
          throw error;
        }
      });
    },

    retrySubmission: () => {
      const requestId = get().activeRequestId;
      if (requestId === null) throw new Error('No failed submission is active');
      const ownership = captureOwnership(requestId);
      return guarded(ownership, async () => {
        setIfCurrent(ownership, { phase: 'processing', error: null });
        try {
          const service = await getCaptureService();
          const result = await service.retrySubmission(requestId);
          if (result.status === 'transcript-confirmation-required') {
            setIfCurrent(ownership, {
              transcript: result.transcript,
              phase: 'transcript-review',
            });
          } else {
            setIfCurrent(ownership, {
              activeMessageId: result.messageId,
              pendingProposalIds: result.pendingProposalIds,
              pendingProposals: result.pendingProposals,
              phase: 'responded',
            });
          }
        } catch (error) {
          setIfCurrent(ownership, { phase: 'error', error: safeError(error) });
          throw error;
        }
      });
    },

    confirmProposal: (confirmationId) => {
      const ownership = captureOwnership(get().activeRequestId);
      return guarded(ownership, async () => {
        const service = await getCaptureService();
        await service.confirmProposal({
          confirmationId,
          localUserActionId: createLocalIntentId(),
          actedAt: new Date().toISOString(),
        });
        setIfCurrent(ownership, (state) => ({
          pendingProposalIds: state.pendingProposalIds.filter((id) => id !== confirmationId),
          pendingProposals: state.pendingProposals.filter((proposal) => proposal.id !== confirmationId),
        }));
      });
    },

    resolveClarification: (confirmationId, choice) => {
      const ownership = captureOwnership(get().activeRequestId);
      return guarded(ownership, async () => {
        const service = await getCaptureService();
        await service.resolveClarification({
          confirmationId,
          choice,
          localUserActionId: createLocalIntentId(),
          actedAt: new Date().toISOString(),
        });
        setIfCurrent(ownership, (state) => ({
          pendingProposalIds: state.pendingProposalIds.filter((id) => id !== confirmationId),
          pendingProposals: state.pendingProposals.filter((proposal) => proposal.id !== confirmationId),
        }));
      });
    },

    discardRecording: async (uri) => {
      const ownership = captureOwnership(get().activeRequestId);
      const service = await getCaptureService();
      await service.discardRecording(uri);
      void isCurrent(ownership);
    },

    abandonVoiceSubmission: async (requestId) => {
      const ownership = captureOwnership(requestId);
      const service = await getCaptureService();
      await service.abandonVoiceSubmission(requestId);
      setIfCurrent(ownership, {
        activeRequestId: null,
        activeRequestKind: null,
        activeMessageId: null,
        transcript: '',
        phase: 'idle',
        error: null,
      });
    },

    clearActiveSession: () => {
      conversationGeneration += 1;
      set({
        activeSessionId: null,
        activeRequestId: null,
        activeRequestKind: null,
        activeMessageId: null,
        transcript: '',
        pendingProposalIds: [],
        pendingProposals: [],
        phase: 'idle',
        isBusy: false,
        error: null,
      });
    },
    clearError: () => set({ error: null }),
    });
  });
}

export const useChatStore = createChatStore();
