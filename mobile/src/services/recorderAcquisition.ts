import type { VoiceDraftState } from './voiceComposerState';

export function isRecorderAcquiring(
  voiceState: VoiceDraftState,
  hasPendingRecording: boolean,
  isNativeRecording: boolean,
): boolean {
  return voiceState === 'recording' && !hasPendingRecording && !isNativeRecording;
}
