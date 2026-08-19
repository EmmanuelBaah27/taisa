import type {
  TranscriptionStreamEvent,
  UsageReceipt,
} from '@taisa/shared';

const MIN_MEAN_TOKEN_LOGPROB = -0.8;
const MAX_LOW_CONFIDENCE_TOKEN_RATIO = 0.25;
const LOW_CONFIDENCE_TOKEN_LOGPROB = -1;
const MAX_MATERIAL_REVISION_RATIO = 0.35;

export interface StreamingTranscriptionInput {
  requestId: string;
  file: File;
  model: string;
  durationSeconds: number;
  usage: UsageReceipt;
  abortSignal?: AbortSignal;
}

export type ProviderTranscriptionEvent =
  | { type: 'transcript.text.delta'; delta: string; logprobs?: Array<{ logprob?: number }> }
  | { type: 'transcript.text.done'; text: string; logprobs?: Array<{ logprob?: number }> };

export type StreamingTranscriptionProvider = (
  input: {
    file: File;
    model: string;
    language: 'en';
    stream: true;
    response_format: 'json';
    include: ['logprobs'];
    chunking_strategy: { type: 'server_vad'; threshold: number };
    temperature: 0;
  },
  options: { maxRetries: 0; signal?: AbortSignal },
) => Promise<AsyncIterable<ProviderTranscriptionEvent>>;

export function classifyTranscriptionEvidence(input: {
  transcript: string;
  speechDetected: boolean;
  tokenLogprobs: readonly number[];
  materialRevisionRatio: number;
}): 'clear' | 'uncertain' | 'no-speech' {
  if (!input.speechDetected || input.transcript.trim().length === 0) return 'no-speech';
  if (input.tokenLogprobs.length === 0) return 'uncertain';

  const meanLogprob = input.tokenLogprobs.reduce((total, value) => total + value, 0)
    / input.tokenLogprobs.length;
  const lowConfidenceRatio = input.tokenLogprobs.filter(
    (value) => value < LOW_CONFIDENCE_TOKEN_LOGPROB,
  ).length / input.tokenLogprobs.length;

  if (
    meanLogprob < MIN_MEAN_TOKEN_LOGPROB
    || lowConfidenceRatio > MAX_LOW_CONFIDENCE_TOKEN_RATIO
    || input.materialRevisionRatio > MAX_MATERIAL_REVISION_RATIO
  ) return 'uncertain';

  return 'clear';
}

function collectLogprobs(
  entries: Array<{ logprob?: number }> | undefined,
): number[] {
  return (entries ?? [])
    .map((entry) => entry.logprob)
    .filter((value): value is number => typeof value === 'number' && Number.isFinite(value));
}

function revisionRatio(provisional: string, completed: string): number {
  if (provisional.length === 0) return 0;
  if (provisional === completed) return 0;
  const longestLength = Math.max(provisional.length, completed.length);
  if (longestLength === 0) return 0;

  let commonPrefixLength = 0;
  while (
    commonPrefixLength < provisional.length
    && commonPrefixLength < completed.length
    && provisional[commonPrefixLength] === completed[commonPrefixLength]
  ) commonPrefixLength += 1;

  return (longestLength - commonPrefixLength) / longestLength;
}

export async function* streamTranscription(
  input: StreamingTranscriptionInput,
  provider: StreamingTranscriptionProvider,
): AsyncGenerator<TranscriptionStreamEvent> {
  let sequence = 0;
  let provisionalTranscript = '';
  let accumulatedLogprobs: number[] = [];
  let terminalEmitted = false;

  try {
    const stream = await provider({
      file: input.file,
      model: input.model,
      language: 'en',
      stream: true,
      response_format: 'json',
      include: ['logprobs'],
      chunking_strategy: { type: 'server_vad', threshold: 0.8 },
      temperature: 0,
    }, {
      maxRetries: 0,
      ...(input.abortSignal ? { signal: input.abortSignal } : {}),
    });

    for await (const event of stream) {
      if (event.type === 'transcript.text.delta') {
        provisionalTranscript += event.delta;
        accumulatedLogprobs.push(...collectLogprobs(event.logprobs));
        yield {
          type: 'transcript.delta',
          requestId: input.requestId,
          sequence: sequence++,
          delta: event.delta,
        };
        continue;
      }

      const transcript = event.text.trim();
      const completedLogprobs = collectLogprobs(event.logprobs);
      const quality = classifyTranscriptionEvidence({
        transcript,
        speechDetected: transcript.length > 0,
        tokenLogprobs: completedLogprobs.length > 0 ? completedLogprobs : accumulatedLogprobs,
        materialRevisionRatio: revisionRatio(provisionalTranscript.trim(), transcript),
      });

      if (quality === 'no-speech') {
        yield { type: 'transcript.no_speech', requestId: input.requestId, sequence: sequence++ };
      } else {
        yield {
          type: 'transcript.completed',
          requestId: input.requestId,
          sequence: sequence++,
          transcript,
          durationSeconds: input.durationSeconds,
          quality,
          usage: input.usage,
        };
      }
      terminalEmitted = true;
      return;
    }
  } catch {
    // The public stream intentionally carries no provider error details.
  }

  if (!terminalEmitted) {
    yield {
      type: 'transcript.failed',
      requestId: input.requestId,
      sequence,
      code: 'TRANSCRIPTION_FAILED',
    };
  }
}
