import { create } from 'zustand';

type RecordingPhase = 'idle' | 'recording' | 'reviewing' | 'processing' | 'complete';

interface UIStore {
  recordingPhase: RecordingPhase;
  isProcessing: boolean;
  chatMorphing: boolean;
  pillBottomInset: number;

  setRecordingPhase: (phase: RecordingPhase) => void;
  setProcessing: (v: boolean) => void;
  setChatMorphing: (v: boolean) => void;
  setPillBottomInset: (v: number) => void;
  resetJournalFlow: () => void;
}

export const useUIStore = create<UIStore>((set) => ({
  recordingPhase: 'idle',
  isProcessing: false,
  chatMorphing: false,
  pillBottomInset: 16,

  setRecordingPhase: (phase) => set({ recordingPhase: phase }),
  setProcessing: (v) => set({ isProcessing: v }),
  setChatMorphing: (v) => set({ chatMorphing: v }),
  setPillBottomInset: (v) => set({ pillBottomInset: v }),
  resetJournalFlow: () => set({ recordingPhase: 'idle', isProcessing: false }),
}));
