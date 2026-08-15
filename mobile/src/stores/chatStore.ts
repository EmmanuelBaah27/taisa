import * as Crypto from 'expo-crypto';
import { create } from 'zustand';
import type { PreferredInputMode } from '@taisa/shared';

import { getPrivateCaptureService } from '../services/localPlatform';
import type { CoachingRequestStatus } from '../repositories/coachingRequestRepository';
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
  activeRequestStatus: CoachingRequestStatus | null;
  activeMessageId: string | null;
  preferredInputMode: PreferredInputMode;
  transcript: string;
  provisionalTranscript: string;
  transcriptionOutcome: 'none' | 'streaming' | 'uncertain' | 'no-speech';
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
  clearTranscriptionDraft: () => void;
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

const abandonableVoiceRequestStatuses = new Set<CoachingRequestStatus>([
  'transcription-pending',
  'transcription-failed',
  'transcript-confirmation-required',
  'coaching-pending',
  'coaching-failed',
]);

export function canAbandonVoiceSubmission(
  request: Pick<ChatStore, 'activeRequestId' | 'activeRequestKind' | 'activeRequestStatus'>,
): boolean {
  return request.activeRequestId !== null &&
    request.activeRequestKind === 'voice' &&
    request.activeRequestStatus !== null &&
    abandonableVoiceRequestStatuses.has(request.activeRequestStatus);
}

function failedRequestStatus(error: unknown): CoachingRequestStatus | null {
  if (
    typeof error === 'object' &&
    error !== null &&
    'phase' in error &&
    (error.phase === 'transcription' || error.phase === 'coaching')
  ) {
    return error.phase === 'transcription' ? 'transcription-failed' : 'coaching-failed';
  }
  return null;
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
    activeRequestStatus: null,
    activeMessageId: null,
    preferredInputMode: 'text',
    transcript: '',
    provisionalTranscript: '',
    transcriptionOutcome: 'none',
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
        activeRequestStatus: null,
        activeMessageId: null,
        preferredInputMode: 'text',
        transcript: '',
        provisionalTranscript: '',
        transcriptionOutcome: 'none',
        pendingProposalIds: [],
        pendingProposals: [],
        phase: 'processing',
        isBusy: false,
        error: null,
      });
      let restored: Awaited<ReturnType<PrivateCaptureService['hydrateConversation']>> | null = null;
      try {
        const service = await getCaptureService();
        restored = await service.hydrateConversation(conversationId);
        if (
          restored.requestKind === 'voice' &&
          restored.requestId !== null &&
          (
            restored.requestStatus === 'transcription-pending' ||
            restored.requestStatus === 'coaching-pending' ||
            restored.requestStatus === 'transcript-confirmation-required'
          )
        ) {
          let resumed = restored.requestStatus === 'transcript-confirmation-required'
            ? await service.confirmTranscript({ requestId: restored.requestId })
            : await service.retrySubmission(restored.requestId);
          if (resumed.status === 'transcript-confirmation-required') {
            resumed = await service.confirmTranscript({ requestId: resumed.requestId });
          }
          if (resumed.status === 'completed') {
            restored = {
              ...restored,
              requestId: resumed.requestId,
              messageId: resumed.messageId,
              requestStatus: 'completed',
              pendingProposals: resumed.pendingProposals,
            };
          }
        }
        const phase: ChatPhase = restored.requestStatus === 'completed'
            ? 'responded'
            : restored.requestStatus === 'transcription-uncertain'
              ? 'idle'
            : restored.requestStatus === null
              ? 'idle'
              : 'error';
        setIfCurrent(ownership, {
          activeSessionId: conversationId,
          activeRequestId: restored.requestId,
          activeRequestKind: restored.requestKind,
          activeRequestStatus: restored.requestStatus,
          activeMessageId: restored.messageId,
          preferredInputMode: restored.preferredInputMode,
          transcript: restored.transcript,
          provisionalTranscript: '',
          transcriptionOutcome: restored.requestStatus === 'transcription-uncertain'
            ? 'uncertain'
            : restored.requestStatus === 'no-speech'
              ? 'no-speech'
              : 'none',
          pendingProposalIds: restored.pendingProposals.map((proposal) => proposal.id),
          pendingProposals: restored.pendingProposals,
          phase,
          error: restored.requestStatus === 'no-speech'
            ? 'I couldn’t hear any clear speech. Try recording again or use the keyboard.'
            : phase === 'error'
              ? 'This submission was interrupted. Your content remains on this device and can be retried.'
            : null,
        });
      } catch (hydrateError) {
        setIfCurrent(ownership, {
          activeSessionId: conversationId,
          activeRequestId: restored?.requestId ?? null,
          activeRequestKind: restored?.requestKind ?? null,
          activeRequestStatus: restored?.requestStatus ?? null,
          activeMessageId: restored?.messageId ?? null,
          preferredInputMode: restored?.preferredInputMode ?? 'text',
          transcript: restored?.transcript ?? '',
          pendingProposalIds: restored?.pendingProposals.map((proposal) => proposal.id) ?? [],
          pendingProposals: restored?.pendingProposals ?? [],
          phase: 'error',
          error: restored === null
            ? 'The local conversation could not be restored.'
            : 'This submission was interrupted. Your content remains on this device and can be retried.',
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
          activeRequestStatus: null,
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
          activeRequestId: null,
          activeRequestKind: 'text',
          activeRequestStatus: null,
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
            activeRequestStatus: 'completed',
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
            activeRequestStatus: failedRequestStatus(error),
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
          provisionalTranscript: '',
          transcriptionOutcome: 'streaming',
          error: null,
          activeSessionId: conversationId,
          activeRequestId: null,
          activeRequestKind: 'voice',
          activeRequestStatus: null,
        });
        try {
          const service = await getCaptureService();
          const result = await service.submitVoiceAndCoach({
            conversationId,
            audioUri,
            durationSeconds,
            typedClarification,
            preferredInputMode: get().preferredInputMode,
            intentId: createLocalIntentId(),
            onTranscriptEvent: (event) => {
              if (event.type !== 'transcript.delta') return;
              setIfCurrent(ownership, (state) => ({
                provisionalTranscript: `${state.provisionalTranscript}${event.delta}`,
              }));
            },
          });
          if (result.status === 'transcription-uncertain') {
            setIfCurrent(ownership, {
              activeRequestId: result.requestId,
              activeMessageId: null,
              activeRequestStatus: 'transcription-uncertain',
              transcript: result.transcript,
              provisionalTranscript: '',
              transcriptionOutcome: 'uncertain',
              phase: 'idle',
            });
          } else if (result.status === 'no-speech') {
            setIfCurrent(ownership, {
              activeRequestId: result.requestId,
              activeMessageId: null,
              activeRequestStatus: 'no-speech',
              provisionalTranscript: '',
              transcriptionOutcome: 'no-speech',
              phase: 'error',
              error: 'I couldn’t hear any clear speech. Try recording again or use the keyboard.',
            });
          } else if (result.status === 'completed') {
            setIfCurrent(ownership, {
              activeRequestId: result.requestId,
              activeMessageId: result.messageId,
              activeRequestStatus: 'completed',
              pendingProposalIds: result.pendingProposalIds,
              pendingProposals: result.pendingProposals,
              provisionalTranscript: '',
              transcriptionOutcome: 'none',
              phase: 'responded',
            });
          }
        } catch (error) {
          const requestId = typeof error === 'object' && error !== null && 'requestId' in error
            ? String(error.requestId)
            : null;
          setIfCurrent(ownership, {
            activeRequestId: requestId,
            activeRequestStatus: failedRequestStatus(error),
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
      setIfCurrent(ownership, {
        transcript,
        activeRequestStatus: 'transcript-confirmation-required',
      });
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
            activeRequestStatus: 'completed',
            phase: 'responded',
          });
        } catch (error) {
          setIfCurrent(ownership, {
            phase: error instanceof Error && error.name === 'SubmissionValidationError'
              ? 'transcript-review'
              : 'error',
            activeRequestStatus: error instanceof Error && error.name === 'SubmissionValidationError'
              ? 'transcript-confirmation-required'
              : failedRequestStatus(error),
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
        setIfCurrent(ownership, {
          phase: 'processing',
          error: null,
          activeMessageId: null,
          pendingProposalIds: [],
          pendingProposals: [],
        });
        try {
          const service = await getCaptureService();
          const result = await service.reviseSubmittedTranscript({ requestId, transcript });
          setIfCurrent(ownership, {
            activeMessageId: result.messageId,
            pendingProposalIds: result.pendingProposalIds,
            pendingProposals: result.pendingProposals,
            transcript,
            activeRequestStatus: 'completed',
            phase: 'responded',
          });
        } catch (error) {
          setIfCurrent(ownership, {
            phase: 'error',
            error: safeError(error),
            activeRequestStatus: failedRequestStatus(error) ?? get().activeRequestStatus,
          });
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
          let result = await service.retrySubmission(requestId);
          if (result.status === 'transcript-confirmation-required') {
            setIfCurrent(ownership, { transcript: result.transcript });
            result = await service.confirmTranscript({ requestId: result.requestId });
          }
          if (result.status === 'completed') {
            setIfCurrent(ownership, {
              activeMessageId: result.messageId,
              pendingProposalIds: result.pendingProposalIds,
              pendingProposals: result.pendingProposals,
              phase: 'responded',
              activeRequestStatus: 'completed',
              provisionalTranscript: '',
              transcriptionOutcome: 'none',
            });
          } else if (result.status === 'transcription-uncertain') {
            setIfCurrent(ownership, {
              transcript: result.transcript,
              phase: 'idle',
              activeRequestStatus: 'transcription-uncertain',
              provisionalTranscript: '',
              transcriptionOutcome: 'uncertain',
            });
          } else if (result.status === 'no-speech') {
            setIfCurrent(ownership, {
              phase: 'error',
              activeRequestStatus: 'no-speech',
              provisionalTranscript: '',
              transcriptionOutcome: 'no-speech',
              error: 'I couldn’t hear any clear speech. Try recording again or use the keyboard.',
            });
          }
        } catch (error) {
          setIfCurrent(ownership, {
            phase: 'error',
            error: safeError(error),
            activeRequestStatus: failedRequestStatus(error) ?? get().activeRequestStatus,
          });
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
        activeRequestStatus: null,
        activeMessageId: null,
        transcript: '',
        provisionalTranscript: '',
        transcriptionOutcome: 'none',
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
        activeRequestStatus: null,
        activeMessageId: null,
        transcript: '',
        provisionalTranscript: '',
        transcriptionOutcome: 'none',
        pendingProposalIds: [],
        pendingProposals: [],
        phase: 'idle',
        isBusy: false,
        error: null,
      });
    },
    clearTranscriptionDraft: () => set({
      transcript: '',
      provisionalTranscript: '',
      transcriptionOutcome: 'none',
    }),
    clearError: () => set({ error: null }),
    });
  });
}

export const useChatStore = createChatStore();
