import { create } from 'zustand';
import * as Crypto from 'expo-crypto';

import { openTaisaDatabase } from '../db/openDatabase';
import type { RepositoryConnection } from '../db/types';
import {
  getConversation,
  listConversations,
  listMessages,
  listRecentConversationMessages,
  searchMessages,
} from '../repositories/conversationRepository';
import {
  listCoachingRequestsByConversation,
  type CoachingRequestStatus,
} from '../repositories/coachingRequestRepository';
import { listMemoryConfirmationsByConversation } from '../repositories/memoryConfirmationRepository';
import { getPrivateCaptureService } from '../services/localPlatform';
import type { PrivateCaptureService } from '../services/privateCapture';

export interface Thread {
  id: string;
  title: string;
  entryId: string | null;
  startedAt: string;
  lastMessageAt: string;
  isLive: boolean;
  isVoice: boolean;
  audioDurationSeconds: number | null;
  lastUserMessage: string | null;
  lastAssistantMessage: string | null;
  pendingRequestStatus: CoachingRequestStatus | null;
  pendingProposalCount: number;
}

export interface ChatMessage {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  created_at: string;
}

export interface ThreadSession {
  id: string;
  title: string;
  entryId: string | null;
  startedAt: string;
  lastMessageAt: string;
  isVoice: boolean;
  audioDurationSeconds: number | null;
  pendingRequestStatus: CoachingRequestStatus | null;
  pendingProposalCount: number;
}

interface ThreadStoreDependencies {
  openDatabase(): Promise<RepositoryConnection>;
  getCaptureService(): Promise<PrivateCaptureService>;
}

interface ThreadStore {
  threads: Thread[];
  currentSession: ThreadSession | null;
  currentMessages: ChatMessage[];
  isLoadingThreads: boolean;
  isLoadingMessages: boolean;
  isSending: boolean;
  error: string | null;
  fetchThreads: () => Promise<void>;
  searchThreads: (query: string) => Promise<void>;
  fetchThread: (sessionId: string) => Promise<void>;
  sendMessage: (sessionId: string, content: string) => Promise<void>;
  clearThread: () => void;
  clearError: () => void;
}

function safeMessage(error: unknown): string {
  return error instanceof Error && error.name === 'SubmissionFailedError'
    ? error.message
    : 'The local conversation could not be updated.';
}

async function summary(database: RepositoryConnection, conversationId: string): Promise<Thread | null> {
  const conversation = await getConversation(database, conversationId);
  if (conversation === null) return null;
  const [recent, requests, confirmations] = await Promise.all([
    listRecentConversationMessages(database, conversation.id, 20),
    latestVisibleRequest(database, conversation.id),
    listMemoryConfirmationsByConversation(database, conversation.id, ['pending', 'confirmed']),
  ]);
  return {
    id: conversation.id,
    title: conversation.title ?? 'Untitled conversation',
    entryId: null,
    startedAt: conversation.createdAt,
    lastMessageAt: recent[0]?.updatedAt ?? conversation.updatedAt,
    isLive: conversation.lifecycle === 'active',
    isVoice: false,
    audioDurationSeconds: null,
    lastUserMessage: recent.find((message) => message.role === 'user')?.content ?? null,
    lastAssistantMessage: recent.find((message) => message.role === 'assistant')?.content ?? null,
    pendingRequestStatus: requests[0]?.status ?? null,
    pendingProposalCount: confirmations.length,
  };
}

async function latestVisibleRequest(
  database: RepositoryConnection,
  conversationId: string,
) {
  const actionable = await listCoachingRequestsByConversation(database, conversationId, [
    'transcription-pending',
    'transcription-failed',
    'transcript-confirmation-required',
    'coaching-pending',
    'coaching-failed',
  ], 1);
  if (actionable.length > 0) return actionable;
  return listCoachingRequestsByConversation(database, conversationId, ['completed'], 1);
}

export function createThreadStore(
  dependencies: ThreadStoreDependencies = {
    openDatabase: openTaisaDatabase,
    getCaptureService: getPrivateCaptureService,
  },
) {
  let sendInFlight: Promise<void> | null = null;
  let localIntentSequence = 0;
  function createLocalIntentId(): string {
    const generated = Crypto.randomUUID();
    return typeof generated === 'string' && generated.length > 0
      ? generated
      : `local-thread-intent-${localIntentSequence += 1}`;
  }
  return create<ThreadStore>((set, get) => ({
    threads: [],
    currentSession: null,
    currentMessages: [],
    isLoadingThreads: false,
    isLoadingMessages: false,
    isSending: false,
    error: null,

    fetchThreads: async () => {
      set({ isLoadingThreads: true, error: null });
      try {
        const database = await dependencies.openDatabase();
        const conversations = await listConversations(database);
        const threads = (await Promise.all(
          conversations.map((conversation) => summary(database, conversation.id)),
        )).filter((item): item is Thread => item !== null);
        set({ threads, isLoadingThreads: false });
      } catch {
        set({ isLoadingThreads: false, error: 'The local conversation history is unavailable.' });
      }
    },

    searchThreads: async (query) => {
      const normalized = query.trim();
      if (!normalized) return get().fetchThreads();
      set({ isLoadingThreads: true, error: null });
      try {
        const database = await dependencies.openDatabase();
        const matches = await searchMessages(database, normalized, 50);
        const ids = [...new Set(matches.map((message) => message.conversationId))];
        const threads = (await Promise.all(ids.map((id) => summary(database, id))))
          .filter((item): item is Thread => item !== null);
        set({ threads, isLoadingThreads: false });
      } catch {
        set({ isLoadingThreads: false, error: 'The local conversation search is unavailable.' });
      }
    },

    fetchThread: async (sessionId) => {
      set({ isLoadingMessages: true, error: null });
      try {
        const database = await dependencies.openDatabase();
        const conversation = await getConversation(database, sessionId);
        if (conversation === null) throw new Error('missing');
        const [messages, requests, confirmations] = await Promise.all([
          listMessages(database, sessionId),
          latestVisibleRequest(database, sessionId),
          listMemoryConfirmationsByConversation(database, sessionId, ['pending', 'confirmed']),
        ]);
        set({
          currentSession: {
            id: conversation.id,
            title: conversation.title ?? 'Untitled conversation',
            entryId: null,
            startedAt: conversation.createdAt,
            lastMessageAt: messages.at(-1)?.updatedAt ?? conversation.updatedAt,
            isVoice: false,
            audioDurationSeconds: null,
            pendingRequestStatus: requests[0]?.status ?? null,
            pendingProposalCount: confirmations.length,
          },
          currentMessages: messages.map((message) => ({
            id: message.id,
            role: message.role,
            content: message.content,
            created_at: message.createdAt,
          })),
          isLoadingMessages: false,
        });
      } catch {
        set({ isLoadingMessages: false, error: 'The local conversation is unavailable.' });
      }
    },

    sendMessage: (sessionId, content) => {
      if (sendInFlight !== null) return sendInFlight;
      set({ isSending: true, error: null });
      const promise = (async () => {
        try {
          const service = await dependencies.getCaptureService();
          await service.submitText({
            conversationId: sessionId,
            content,
            intentId: createLocalIntentId(),
          });
          await get().fetchThread(sessionId);
          set({ isSending: false });
        } catch (error) {
          await get().fetchThread(sessionId);
          set({ isSending: false, error: safeMessage(error) });
        }
      })().finally(() => {
        if (sendInFlight === promise) sendInFlight = null;
      });
      sendInFlight = promise;
      return promise;
    },

    clearThread: () => set({ currentSession: null, currentMessages: [] }),
    clearError: () => set({ error: null }),
  }));
}

export const useThreadStore = createThreadStore();
