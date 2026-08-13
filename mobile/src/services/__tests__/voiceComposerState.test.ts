import {
  createVoiceComposerState,
  reduceVoiceComposer,
} from '../voiceComposerState';

describe('voice composer state', () => {
  test('a voice-ready reply stays idle until its full control explicitly starts recording', () => {
    const ready = createVoiceComposerState('voice');

    expect(ready).toMatchObject({ mode: 'voice', voice: 'ready' });
    expect(reduceVoiceComposer(ready, { type: 'start-voice' })).toMatchObject({
      mode: 'voice',
      voice: 'recording',
    });
  });

  test('a completed voice response returns to ready instead of reactivating the microphone', () => {
    const submittingVoice = {
      ...createVoiceComposerState('voice'),
      voice: 'paused' as const,
      submitting: true,
    };

    expect(reduceVoiceComposer(submittingVoice, { type: 'reset' })).toMatchObject({
      mode: 'voice',
      voice: 'ready',
      submitting: false,
    });
  });

  test('a failed voice submission retains the paused voice draft and selected mode', () => {
    const failed = reduceVoiceComposer(
      {
        ...createVoiceComposerState('voice'),
        voice: 'paused',
        submitting: true,
      },
      { type: 'submission-failed' },
    );

    expect(failed).toMatchObject({ mode: 'voice', voice: 'paused', submitting: false });
  });

  test('cancelling a paused voice draft returns to a non-recording ready reply', () => {
    expect(reduceVoiceComposer(
      { ...createVoiceComposerState('voice'), voice: 'paused' },
      { type: 'reset' },
    )).toMatchObject({ mode: 'voice', voice: 'ready' });
  });

  test('explicit voice entry starts in recording mode', () => {
    expect(reduceVoiceComposer(createVoiceComposerState(), { type: 'start-voice' })).toMatchObject({
      mode: 'voice',
      voice: 'recording',
    });
  });

  test('pause and resume keep the same voice draft', () => {
    const recording = reduceVoiceComposer(createVoiceComposerState(), { type: 'start-voice' });
    const paused = reduceVoiceComposer(recording, { type: 'pause-voice' });
    expect(paused.voice).toBe('paused');
    expect(reduceVoiceComposer(paused, { type: 'resume-voice' }).voice).toBe('recording');
  });

  test.each(['speech', 'uncertain'] as const)(
    'switching to text preserves %s audio as a paused draft',
    (activity) => {
      const recording = reduceVoiceComposer(createVoiceComposerState(), { type: 'start-voice' });
      expect(reduceVoiceComposer(recording, { type: 'switch-to-text', activity })).toMatchObject({
        mode: 'text',
        voice: 'paused',
      });
    },
  );

  test('switching to text discards silence instead of creating a draft', () => {
    const recording = reduceVoiceComposer(createVoiceComposerState(), { type: 'start-voice' });
    expect(reduceVoiceComposer(recording, { type: 'switch-to-text', activity: 'silence' })).toMatchObject({
      mode: 'text',
      voice: 'none',
    });
  });

  test('returning from text to an existing voice draft stays paused until explicit resume', () => {
    const pausedText = {
      ...createVoiceComposerState(),
      mode: 'text' as const,
      voice: 'paused' as const,
      text: 'Clarification',
    };
    expect(reduceVoiceComposer(pausedText, { type: 'switch-to-voice' })).toMatchObject({
      mode: 'voice',
      voice: 'paused',
      text: 'Clarification',
    });
  });

  test('text deletion removes only text', () => {
    const state = {
      ...createVoiceComposerState(),
      mode: 'voice' as const,
      voice: 'paused' as const,
      text: 'Clarification',
    };
    expect(reduceVoiceComposer(state, { type: 'delete-text' })).toMatchObject({
      voice: 'paused',
      text: '',
    });
  });

  test('voice deletion requires an explicit confirmation', () => {
    const state = {
      ...createVoiceComposerState(),
      mode: 'text' as const,
      voice: 'paused' as const,
    };
    const requested = reduceVoiceComposer(state, { type: 'request-delete-voice' });
    expect(requested.voice).toBe('paused');
    expect(requested.confirmDeleteVoice).toBe(true);
    expect(reduceVoiceComposer(requested, { type: 'confirm-delete-voice' })).toMatchObject({
      mode: 'voice',
      voice: 'ready',
      confirmDeleteVoice: false,
    });
  });

  test('send is deliberate and preserves both inputs while submission is pending', () => {
    const state = {
      ...createVoiceComposerState(),
      mode: 'voice' as const,
      voice: 'paused' as const,
      text: 'Clarification',
    };
    expect(reduceVoiceComposer(state, { type: 'send' })).toMatchObject({
      submitting: true,
      voice: 'paused',
      text: 'Clarification',
    });
  });
});
