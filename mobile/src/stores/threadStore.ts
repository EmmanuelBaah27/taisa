import { create } from 'zustand';
import api from '../services/api';

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

interface ThreadStore {
  threads: Thread[];
  currentSession: ThreadSession | null;
  currentMessages: ChatMessage[];
  isLoadingThreads: boolean;
  isLoadingMessages: boolean;
  isSending: boolean;
  error: string | null;

  fetchThreads: () => Promise<void>;
  fetchThread: (sessionId: string) => Promise<void>;
  sendMessage: (sessionId: string, content: string) => Promise<void>;
  clearThread: () => void;
  clearError: () => void;
}

export const useThreadStore = create<ThreadStore>((set, get) => ({
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
      const res = await api.get('/chat/sessions');
      set({ threads: res.data.data.sessions, isLoadingThreads: false });
    } catch (e: any) {
      set({ isLoadingThreads: false, error: e.message });
    }
  },

  fetchThread: async (sessionId: string) => {
    set({ isLoadingMessages: true, error: null });
    try {
      const res = await api.get(`/chat/session/${sessionId}`);
      set({
        currentSession: res.data.data.session,
        currentMessages: res.data.data.messages,
        isLoadingMessages: false,
      });
    } catch (e: any) {
      set({ isLoadingMessages: false, error: e.message });
    }
  },

  sendMessage: async (sessionId: string, content: string) => {
    const optimisticMsg: ChatMessage = {
      id: `temp-${Date.now()}`,
      role: 'user',
      content,
      created_at: new Date().toISOString(),
    };
    set(state => ({
      currentMessages: [...state.currentMessages, optimisticMsg],
      isSending: true,
    }));

    try {
      const res = await api.post('/chat/message', { sessionId, message: content });
      const assistantMsg: ChatMessage = {
        id: `temp-reply-${Date.now()}`,
        role: 'assistant',
        content: res.data.data.reply,
        created_at: new Date().toISOString(),
      };
      set(state => ({
        currentMessages: [...state.currentMessages, assistantMsg],
        isSending: false,
      }));
    } catch (e: any) {
      const serverMsg = (e as any)?.response?.data?.error?.message;
      set(state => ({
        currentMessages: state.currentMessages.filter(m => m.id !== optimisticMsg.id),
        isSending: false,
        error: serverMsg ?? e.message,
      }));
    }
  },

  clearThread: () => set({ currentSession: null, currentMessages: [] }),
  clearError: () => set({ error: null }),
}));
