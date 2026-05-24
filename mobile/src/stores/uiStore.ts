import { create } from 'zustand';

type RecordingPhase = 'idle' | 'recording' | 'reviewing' | 'processing' | 'complete';

interface UIStore {
  recordingPhase: RecordingPhase;
  isProcessing: boolean;
  chatMorphing: boolean;

  setRecordingPhase: (phase: RecordingPhase) => void;
  setProcessing: (v: boolean) => void;
  setChatMorphing: (v: boolean) => void;
  resetJournalFlow: () => void;
}

export const useUIStore = create<UIStore>((set) => ({
  recordingPhase: 'idle',
  isProcessing: false,
  chatMorphing: false,

  setRecordingPhase: (phase) => set({ recordingPhase: phase }),
  setProcessing: (v) => set({ isProcessing: v }),
  setChatMorphing: (v) => set({ chatMorphing: v }),
  resetJournalFlow: () => set({ recordingPhase: 'idle', isProcessing: false }),
}));
