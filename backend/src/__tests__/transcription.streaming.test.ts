import { isTranscriptionStreamEvent } from '@taisa/shared';

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
