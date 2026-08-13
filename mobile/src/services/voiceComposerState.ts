import type { VoiceActivitySummary } from './voiceActivity';

export type VoiceComposerMode = 'voice' | 'text';
export type VoiceDraftState = 'none' | 'ready' | 'recording' | 'paused';

export interface VoiceComposerState {
  mode: VoiceComposerMode;
  voice: VoiceDraftState;
  text: string;
  confirmDeleteVoice: boolean;
  submitting: boolean;
}

export type VoiceComposerAction =
  | { type: 'start-voice' }
  | { type: 'pause-voice' }
  | { type: 'resume-voice' }
  | { type: 'switch-to-text'; activity: VoiceActivitySummary }
  | { type: 'switch-to-voice' }
  | { type: 'set-text'; text: string }
  | { type: 'delete-text' }
  | { type: 'request-delete-voice' }
  | { type: 'cancel-delete-voice' }
  | { type: 'confirm-delete-voice' }
  | { type: 'send' }
  | { type: 'submission-failed' }
  | { type: 'restore-mode'; mode: VoiceComposerMode }
  | { type: 'reset' };

export function createVoiceComposerState(mode: VoiceComposerMode = 'text'): VoiceComposerState {
  return {
    mode,
    voice: mode === 'voice' ? 'ready' : 'none',
    text: '',
    confirmDeleteVoice: false,
    submitting: false,
  };
}

export function reduceVoiceComposer(
  state: VoiceComposerState,
  action: VoiceComposerAction,
): VoiceComposerState {
  switch (action.type) {
    case 'start-voice':
      return { ...state, mode: 'voice', voice: 'recording', confirmDeleteVoice: false };
    case 'pause-voice':
      return state.voice === 'recording' ? { ...state, voice: 'paused' } : state;
    case 'resume-voice':
      return state.voice === 'paused'
        ? { ...state, mode: 'voice', voice: 'recording', confirmDeleteVoice: false }
        : state;
    case 'switch-to-text':
      return {
        ...state,
        mode: 'text',
        voice: action.activity === 'silence' ? 'none' : 'paused',
        confirmDeleteVoice: false,
      };
    case 'switch-to-voice':
      return state.voice === 'none' || state.voice === 'ready'
        ? { ...state, mode: 'voice', voice: 'ready', confirmDeleteVoice: false }
        : { ...state, mode: 'voice', voice: 'paused', confirmDeleteVoice: false };
    case 'set-text':
      return { ...state, text: action.text };
    case 'delete-text':
      return { ...state, text: '' };
    case 'request-delete-voice':
      return state.voice === 'none' ? state : { ...state, confirmDeleteVoice: true };
    case 'cancel-delete-voice':
      return { ...state, confirmDeleteVoice: false };
    case 'confirm-delete-voice':
      return { ...state, mode: 'voice', voice: 'ready', confirmDeleteVoice: false };
    case 'send':
      return state.voice === 'none' && state.text.trim().length === 0
        ? state
        : { ...state, submitting: true, confirmDeleteVoice: false };
    case 'submission-failed':
      return { ...state, submitting: false };
    case 'restore-mode':
      return createVoiceComposerState(action.mode);
    case 'reset':
      return createVoiceComposerState(state.mode);
  }
}
