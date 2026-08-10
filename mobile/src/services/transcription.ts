import * as Crypto from 'expo-crypto';
import type { UsageReceipt } from '@taisa/shared';

import api from './api';

interface HttpClient {
  post(path: string, body: unknown, config?: unknown): Promise<{ data: unknown }>;
}

export interface TranscriptionRequest {
  requestId: string;
  audioUri: string;
  durationSeconds: number;
}

export interface TranscriptionResult {
  transcript: string;
  durationSeconds: number;
  usage: UsageReceipt;
}

export class TranscriptionClientError extends Error {
  readonly code = 'TRANSCRIPTION_REQUEST_FAILED';

  constructor() {
    super('Taisa could not transcribe this recording. The recording remains on this device.');
    this.name = 'TranscriptionClientError';
  }
}

function isResult(value: unknown): value is TranscriptionResult {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return false;
  const result = value as Record<string, unknown>;
  const usage = result.usage as Record<string, unknown> | undefined;
  return typeof result.transcript === 'string' && result.transcript.trim().length > 0 &&
    typeof result.durationSeconds === 'number' && Number.isFinite(result.durationSeconds) &&
    result.durationSeconds > 0 && usage !== undefined &&
    usage.provider === 'openai' && typeof usage.model === 'string' && usage.model.length > 0 &&
    typeof usage.estimatedCostUsd === 'number' && Number.isFinite(usage.estimatedCostUsd) &&
    usage.estimatedCostUsd >= 0 &&
    (usage.audioSeconds === undefined || (
      typeof usage.audioSeconds === 'number' && Number.isFinite(usage.audioSeconds) &&
      usage.audioSeconds >= 0
    ));
}

export function createTranscriptionClient(http: HttpClient) {
  return async function requestTranscription(
    request: TranscriptionRequest,
  ): Promise<TranscriptionResult> {
    const formData = new FormData();

    // React Native FormData accepts file objects.
    formData.append('audio', {
      uri: request.audioUri,
      name: 'recording.m4a',
      type: 'audio/m4a',
    } as any);

    formData.append('durationSeconds', String(request.durationSeconds));

    try {
      const response = await http.post('/transcribe', formData, {
        headers: {
          'Content-Type': 'multipart/form-data',
          'x-request-id': request.requestId,
        },
        timeout: 60_000,
      });
      const envelope = response.data as { success?: unknown; data?: unknown };
      if (envelope?.success !== true || !isResult(envelope.data)) {
        throw new TranscriptionClientError();
      }
      return envelope.data;
    } catch {
      throw new TranscriptionClientError();
    }
  };
}

export const requestTranscription = createTranscriptionClient(api);

export async function transcribeAudio(audioUri: string, durationSeconds: number): Promise<string> {
  const result = await requestTranscription({
    requestId: Crypto.randomUUID(),
    audioUri,
    durationSeconds,
  });
  return result.transcript;
}
