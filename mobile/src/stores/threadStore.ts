import { create } from 'zustand';

import { openTaisaDatabase } from '../db/openDatabase';
import type { RepositoryConnection } from '../db/types';
import {
  getConversation,
  listConversations,
  listMessages,
  listRecentMessages,
  searchMessages,
} from '../repositories/conversationRepository';
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
  const recent = await listRecentMessages(database, conversation.id, 20);
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
  };
}

export function createThreadStore(
  dependencies: ThreadStoreDependencies = {
    openDatabase: openTaisaDatabase,
    getCaptureService: getPrivateCaptureService,
  },
) {
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
        const messages = await listMessages(database, sessionId);
        set({
          currentSession: {
            id: conversation.id,
            title: conversation.title ?? 'Untitled conversation',
            entryId: null,
            startedAt: conversation.createdAt,
            lastMessageAt: messages.at(-1)?.updatedAt ?? conversation.updatedAt,
            isVoice: false,
            audioDurationSeconds: null,
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

    sendMessage: async (sessionId, content) => {
      set({ isSending: true, error: null });
      try {
        const service = await dependencies.getCaptureService();
        await service.submitText({ conversationId: sessionId, content });
        await get().fetchThread(sessionId);
        set({ isSending: false });
      } catch (error) {
        await get().fetchThread(sessionId);
        set({ isSending: false, error: safeMessage(error) });
      }
    },

    clearThread: () => set({ currentSession: null, currentMessages: [] }),
    clearError: () => set({ error: null }),
  }));
}

export const useThreadStore = createThreadStore();
