import { reduceVoiceComposerTransition } from '../voiceComposerTransition';

describe('voice composer Reply transition', () => {
  test('waits for the Reply exit before recording and ignores repeated presses', () => {
    const exiting = reduceVoiceComposerTransition('idle', 'press');

    expect(exiting).toBe('exiting');
    expect(reduceVoiceComposerTransition(exiting, 'press')).toBe('exiting');
    expect(reduceVoiceComposerTransition(exiting, 'exit-complete')).toBe('recording');
    expect(reduceVoiceComposerTransition('idle', 'exit-complete')).toBe('idle');
    expect(reduceVoiceComposerTransition('recording', 'reset')).toBe('idle');
    expect(reduceVoiceComposerTransition('recording', 'start-failed')).toBe('idle');
  });
});
