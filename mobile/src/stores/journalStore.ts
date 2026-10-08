import { create } from 'zustand';
import type { JournalEntry, EntryAnalysis } from '@taisa/shared';
import api from '../services/api';

interface JournalStore {
  entries: JournalEntry[];
  currentEntry: JournalEntry | null;
  currentAnalysis: EntryAnalysis | null;
  isLoading: boolean;
  error: string | null;

  fetchEntries: () => Promise<void>;
  createEntry: (data: { rawTranscript: string; editedTranscript?: string; audioDurationSeconds?: number; recordedAt: string }) => Promise<JournalEntry>;
  analyzeEntry: (entryId: string) => Promise<EntryAnalysis>;
  setCurrentEntry: (entry: JournalEntry | null) => void;
  clearError: () => void;
  clearForAuthorityReplacement: () => void;
}

export const useJournalStore = create<JournalStore>((set, get) => ({
  entries: [],
  currentEntry: null,
  currentAnalysis: null,
  isLoading: false,
  error: null,

  fetchEntries: async () => {
    set({ isLoading: true, error: null });
    try {
      const res = await api.get('/entries', { params: { limit: 20 } });
      set({ entries: res.data.data.items, isLoading: false });
    } catch (e: any) {
      set({ isLoading: false, error: e.message });
    }
  },

  createEntry: async (data) => {
    const res = await api.post('/entries', { ...data, inputType: 'voice' });
    const entry: JournalEntry = res.data.data;
    set(state => ({ entries: [entry, ...state.entries] }));
    return entry;
  },

  analyzeEntry: async (entryId: string) => {
    const res = await api.post(`/analyze/${entryId}`);
    const analysis: EntryAnalysis = res.data.data;
    set({ currentAnalysis: analysis });
    // Update entry status in list
    set(state => ({
      entries: state.entries.map(e => e.id === entryId ? { ...e, status: 'complete', analysisId: analysis.id } : e),
    }));
    return analysis;
  },

  setCurrentEntry: (entry) => set({ currentEntry: entry, currentAnalysis: null }),
  clearError: () => set({ error: null }),
  clearForAuthorityReplacement: () => set({
    entries: [],
    currentEntry: null,
    currentAnalysis: null,
    isLoading: false,
    error: null,
  }),
}));
