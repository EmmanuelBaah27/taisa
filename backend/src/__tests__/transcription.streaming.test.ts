import { isTranscriptionStreamEvent } from '@taisa/shared';
import {
  classifyTranscriptionEvidence,
  streamTranscription,
  type ProviderTranscriptionEvent,
} from '../services/transcription/streamingTranscription';

const requestId = '11111111-1111-4111-8111-111111111111';

describe('transcription stream contract', () => {
  test('accepts a typed transcript delta', () => {
    expect(isTranscriptionStreamEvent({
      type: 'transcript.delta',
      requestId,
      sequence: 1,
      delta: 'I led',
    })).toBe(true);
  });

  test('rejects provider confidence fields at the public boundary', () => {
    expect(isTranscriptionStreamEvent({
      type: 'transcript.delta',
      requestId,
      sequence: 1,
      delta: 'I led',
      token_logprobs: [],
    })).toBe(false);
  });

  test('accepts a complete transcript with a usage receipt', () => {
    expect(isTranscriptionStreamEvent({
      type: 'transcript.completed',
      requestId,
      sequence: 2,
      transcript: 'I led the review',
      durationSeconds: 4,
      quality: 'clear',
      usage: {
        provider: 'openai',
        model: 'fixture-transcription',
        audioSeconds: 4,
        estimatedCostUsd: 0.0004,
      },
    })).toBe(true);
  });

  test.each([
    { type: 'transcript.delta', requestId: 'not-a-uuid', sequence: 0, delta: 'text' },
    { type: 'transcript.delta', requestId, sequence: -1, delta: 'text' },
    { type: 'transcript.completed', requestId, sequence: 1, transcript: '', durationSeconds: 0, quality: 'clear', usage: {} },
    { type: 'transcript.failed', requestId, sequence: 1, code: 'RAW_PROVIDER_ERROR' },
  ])('rejects malformed public event %#', (event) => {
    expect(isTranscriptionStreamEvent(event)).toBe(false);
  });
});

describe('transcription recognition evidence', () => {
  test.each([
    [{ transcript: '', speechDetected: false, tokenLogprobs: [], materialRevisionRatio: 0 }, 'no-speech'],
    [{ transcript: 'I led the review', speechDetected: true, tokenLogprobs: [-0.12, -0.18], materialRevisionRatio: 0.05 }, 'clear'],
    [{ transcript: 'unclear draft', speechDetected: true, tokenLogprobs: [-1.3, -1.1], materialRevisionRatio: 0.1 }, 'uncertain'],
    [{ transcript: 'changing draft', speechDetected: true, tokenLogprobs: [-0.2], materialRevisionRatio: 0.55 }, 'uncertain'],
    [{ transcript: 'words without evidence', speechDetected: true, tokenLogprobs: [], materialRevisionRatio: 0 }, 'uncertain'],
  ] as const)('classifies recognition evidence without interpreting meaning: %#', (input, expected) => {
    expect(classifyTranscriptionEvidence(input)).toBe(expected);
  });

  test('accepts Thanks for watching when strong speech evidence supports it', () => {
    expect(classifyTranscriptionEvidence({
      transcript: 'Thanks for watching',
      speechDetected: true,
      tokenLogprobs: [-0.08, -0.11, -0.09],
      materialRevisionRatio: 0,
    })).toBe('clear');
  });
});

describe('provider streaming adapter', () => {
  const input = {
    requestId,
    file: new File(['audio'], 'audio.m4a', { type: 'audio/mp4' }),
    model: 'gpt-4o-mini-transcribe',
    durationSeconds: 4,
    usage: {
      provider: 'openai' as const,
      model: 'gpt-4o-mini-transcribe',
      audioSeconds: 4,
      estimatedCostUsd: 0.0004,
    },
  };

  async function* providerEvents(events: ProviderTranscriptionEvent[]) {
    yield* events;
  }

  test('emits ordered public deltas and one clear completion without provider fields', async () => {
    const provider = jest.fn(async () => providerEvents([
      { type: 'transcript.text.delta', delta: 'I led ', logprobs: [{ logprob: -0.1 }] },
      { type: 'transcript.text.delta', delta: 'the review', logprobs: [{ logprob: -0.2 }] },
      { type: 'transcript.text.done', text: 'I led the review', logprobs: [{ logprob: -0.1 }, { logprob: -0.2 }] },
    ]));

    const events = [];
    for await (const event of streamTranscription(input, provider)) events.push(event);

    expect(events).toEqual([
      { type: 'transcript.delta', requestId, sequence: 0, delta: 'I led ' },
      { type: 'transcript.delta', requestId, sequence: 1, delta: 'the review' },
      {
        type: 'transcript.completed',
        requestId,
        sequence: 2,
        transcript: 'I led the review',
        durationSeconds: 4,
        quality: 'clear',
        usage: input.usage,
      },
    ]);
    expect(provider).toHaveBeenCalledWith(expect.objectContaining({
      model: 'gpt-4o-mini-transcribe',
      stream: true,
      response_format: 'json',
      include: ['logprobs'],
    }), { maxRetries: 0 });
  });

  test('emits no-speech when the provider returns no recognized text', async () => {
    const provider = jest.fn(async () => providerEvents([
      { type: 'transcript.text.done', text: '', logprobs: [] },
    ]));

    const events = [];
    for await (const event of streamTranscription(input, provider)) events.push(event);

    expect(events).toEqual([
      { type: 'transcript.no_speech', requestId, sequence: 0 },
    ]);
  });

  test('treats a strong done-only result as clear rather than as a revision', async () => {
    const provider = jest.fn(async () => providerEvents([
      {
        type: 'transcript.text.done',
        text: 'I led the review',
        logprobs: [{ logprob: -0.1 }, { logprob: -0.2 }],
      },
    ]));

    const events = [];
    for await (const event of streamTranscription(input, provider)) events.push(event);

    expect(events).toEqual([
      expect.objectContaining({ type: 'transcript.completed', quality: 'clear' }),
    ]);
  });

  test('emits one uncertain completion when confidence evidence is missing', async () => {
    const provider = jest.fn(async () => providerEvents([
      { type: 'transcript.text.delta', delta: 'Possible words' },
      { type: 'transcript.text.done', text: 'Possible words' },
    ]));

    const events = [];
    for await (const event of streamTranscription(input, provider)) events.push(event);

    expect(events.at(-1)).toMatchObject({
      type: 'transcript.completed',
      quality: 'uncertain',
      transcript: 'Possible words',
    });
    expect(events.filter((event) => event.type !== 'transcript.delta')).toHaveLength(1);
  });
});
