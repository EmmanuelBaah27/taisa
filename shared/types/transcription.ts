import type { UsageReceipt } from './coaching';

export type TranscriptionQuality = 'clear' | 'uncertain';

export interface TranscriptionCompletedData {
  transcript: string;
  durationSeconds: number;
  quality: TranscriptionQuality;
  usage: UsageReceipt;
}

export type TranscriptionStreamEvent =
  | { type: 'transcript.delta'; requestId: string; sequence: number; delta: string }
  | ({ type: 'transcript.completed'; requestId: string; sequence: number } & TranscriptionCompletedData)
  | { type: 'transcript.no_speech'; requestId: string; sequence: number }
  | { type: 'transcript.failed'; requestId: string; sequence: number; code: 'TRANSCRIPTION_FAILED' };

const REQUEST_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function hasOnlyKeys(value: Record<string, unknown>, allowedKeys: readonly string[]): boolean {
  const allowed = new Set(allowedKeys);
  return Object.keys(value).every((key) => allowed.has(key));
}

function isUsageReceipt(value: unknown): value is UsageReceipt {
  if (!isRecord(value) || !hasOnlyKeys(value, [
    'provider',
    'model',
    'inputTokens',
    'outputTokens',
    'audioSeconds',
    'estimatedCostUsd',
  ])) return false;

  const optionalCounts = ['inputTokens', 'outputTokens', 'audioSeconds'] as const;
  return (value.provider === 'openai' || value.provider === 'anthropic')
    && typeof value.model === 'string'
    && value.model.length > 0
    && typeof value.estimatedCostUsd === 'number'
    && Number.isFinite(value.estimatedCostUsd)
    && value.estimatedCostUsd >= 0
    && optionalCounts.every((key) => value[key] === undefined || (
      typeof value[key] === 'number'
      && Number.isFinite(value[key])
      && (value[key] as number) >= 0
    ));
}

function hasEventEnvelope(value: Record<string, unknown>): boolean {
  return typeof value.requestId === 'string'
    && REQUEST_ID_PATTERN.test(value.requestId)
    && Number.isInteger(value.sequence)
    && (value.sequence as number) >= 0;
}

export function isTranscriptionStreamEvent(value: unknown): value is TranscriptionStreamEvent {
  if (!isRecord(value) || !hasEventEnvelope(value)) return false;

  switch (value.type) {
    case 'transcript.delta':
      return hasOnlyKeys(value, ['type', 'requestId', 'sequence', 'delta'])
        && typeof value.delta === 'string';
    case 'transcript.completed':
      return hasOnlyKeys(value, [
        'type',
        'requestId',
        'sequence',
        'transcript',
        'durationSeconds',
        'quality',
        'usage',
      ])
        && typeof value.transcript === 'string'
        && value.transcript.trim().length > 0
        && typeof value.durationSeconds === 'number'
        && Number.isFinite(value.durationSeconds)
        && value.durationSeconds > 0
        && (value.quality === 'clear' || value.quality === 'uncertain')
        && isUsageReceipt(value.usage);
    case 'transcript.no_speech':
      return hasOnlyKeys(value, ['type', 'requestId', 'sequence']);
    case 'transcript.failed':
      return hasOnlyKeys(value, ['type', 'requestId', 'sequence', 'code'])
        && value.code === 'TRANSCRIPTION_FAILED';
    default:
      return false;
  }
}
