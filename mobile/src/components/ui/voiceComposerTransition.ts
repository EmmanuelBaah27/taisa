export type VoiceComposerTransitionState = 'idle' | 'exiting' | 'recording';
export type VoiceComposerTransitionEvent = 'press' | 'exit-complete' | 'reset' | 'start-failed';

export function reduceVoiceComposerTransition(
  state: VoiceComposerTransitionState,
  event: VoiceComposerTransitionEvent,
): VoiceComposerTransitionState {
  if (state === 'idle' && event === 'press') return 'exiting';
  if (state === 'exiting' && event === 'exit-complete') return 'recording';
  if (state === 'recording' && (event === 'reset' || event === 'start-failed')) return 'idle';
  return state;
}
