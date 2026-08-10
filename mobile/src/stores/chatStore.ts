import * as Crypto from 'expo-crypto';
import { create } from 'zustand';

import { getPrivateCaptureService } from '../services/localPlatform';
import type { PendingProposal, PrivateCaptureService } from '../services/privateCapture';

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
  error: string | null;
  setActiveSessionId: (id: string) => void;
  setPhase: (phase: ChatPhase) => void;
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
  clearActiveSession: () => void;
  clearError: () => void;
}

type CaptureServiceProvider = () => Promise<PrivateCaptureService>;

function safeError(error: unknown): string {
  return error instanceof Error && error.name === 'SubmissionFailedError'
    ? error.message
    : 'Taisa could not complete this action. Your content remains on this device.';
}

export function createChatStore(
  getCaptureService: CaptureServiceProvider = getPrivateCaptureService,
) {
  return create<ChatStore>((set, get) => ({
    activeSessionId: null,
    activeRequestId: null,
    activeMessageId: null,
    transcript: '',
    pendingProposalIds: [],
    pendingProposals: [],
    phase: 'idle',
    error: null,
    setActiveSessionId: (id) => set({ activeSessionId: id }),
    setPhase: (phase) => set({ phase }),

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

    submitText: async (conversationId, content) => {
      set({ phase: 'processing', error: null, activeSessionId: conversationId });
      try {
        const service = await getCaptureService();
        const result = await service.submitText({ conversationId, content });
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
    },

    submitVoice: async (conversationId, audioUri, durationSeconds) => {
      set({ phase: 'transcribing', error: null, activeSessionId: conversationId });
      try {
        const service = await getCaptureService();
        const result = await service.submitVoice({ conversationId, audioUri, durationSeconds });
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
    },

    updateTranscript: async (transcript) => {
      const requestId = get().activeRequestId;
      if (requestId === null) throw new Error('No transcript is active');
      const service = await getCaptureService();
      await service.updateTranscript({ requestId, transcript });
      set({ transcript });
    },

    confirmTranscript: async () => {
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
        set({ phase: 'error', error: safeError(error) });
        throw error;
      }
    },

    retrySubmission: async () => {
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
    },

    confirmProposal: async (confirmationId) => {
      const service = await getCaptureService();
      await service.confirmProposal({
        confirmationId,
        localUserActionId: Crypto.randomUUID(),
        actedAt: new Date().toISOString(),
      });
      set((state) => ({
        pendingProposalIds: state.pendingProposalIds.filter((id) => id !== confirmationId),
        pendingProposals: state.pendingProposals.filter((proposal) => proposal.id !== confirmationId),
      }));
    },

    clearActiveSession: () => set({
      activeSessionId: null,
      activeRequestId: null,
      activeMessageId: null,
      transcript: '',
      pendingProposalIds: [],
      pendingProposals: [],
      phase: 'idle',
      error: null,
    }),
    clearError: () => set({ error: null }),
  }));
}

export const useChatStore = createChatStore();
