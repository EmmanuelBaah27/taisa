import { create } from 'zustand';

type RecordingPhase = 'idle' | 'recording' | 'reviewing' | 'processing' | 'complete';

interface UIStore {
  recordingPhase: RecordingPhase;
  isProcessing: boolean;
  chatMorphing: boolean;
  voiceAutoStartPending: boolean;

  setRecordingPhase: (phase: RecordingPhase) => void;
  setProcessing: (v: boolean) => void;
  setChatMorphing: (v: boolean) => void;
  openVoiceCapture: () => void;
  consumeVoiceAutoStart: () => boolean;
  resetJournalFlow: () => void;
}

export const useUIStore = create<UIStore>((set, get) => ({
  recordingPhase: 'idle',
  isProcessing: false,
  chatMorphing: false,
  voiceAutoStartPending: false,

  setRecordingPhase: (phase) => set({ recordingPhase: phase }),
  setProcessing: (v) => set({ isProcessing: v }),
  setChatMorphing: (v) => set({ chatMorphing: v }),
  openVoiceCapture: () => set({ chatMorphing: true, voiceAutoStartPending: true }),
  consumeVoiceAutoStart: () => {
    if (!get().voiceAutoStartPending) return false;
    set({ voiceAutoStartPending: false });
    return true;
  },
  resetJournalFlow: () => set({ recordingPhase: 'idle', isProcessing: false }),
}));
