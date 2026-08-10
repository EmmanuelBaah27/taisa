import type { UsageReceipt } from '@taisa/shared';

import type { RepositoryConnection, RepositoryTransaction } from '../db/types';
import { toDatabaseMutationPayload } from './mutationPayload';
import { claimMutation, requireExactlyOneAffectedRow } from './mutationReceipt';

export type CoachingRequestKind = 'text' | 'voice';
export type CoachingRequestStatus =
  | 'transcription-pending'
  | 'transcription-failed'
  | 'transcript-confirmation-required'
  | 'coaching-pending'
  | 'coaching-failed'
  | 'completed';

export interface LocalCoachingRequest {
  id: string;
  conversationId: string;
  userMessageId: string;
  transcriptionRequestId: string | null;
  kind: CoachingRequestKind;
  status: CoachingRequestStatus;
  audioUri: string | null;
  audioDurationSeconds: number | null;
  transcriptConfirmedAt: string | null;
  assistantMessageId: string | null;
  stance: 'mirror' | 'nudge' | 'challenge' | 'direct' | null;
  contextManifestJson: string | null;
  errorCode: string | null;
  attemptCount: number;
  submittedAt: string;
  createdAt: string;
  updatedAt: string;
}

interface CoachingRequestRow {
  id: string;
  conversation_id: string;
  user_message_id: string;
  transcription_request_id: string | null;
  kind: CoachingRequestKind;
  status: CoachingRequestStatus;
  audio_uri: string | null;
  audio_duration_seconds: number | null;
  transcript_confirmed_at: string | null;
  assistant_message_id: string | null;
  stance: LocalCoachingRequest['stance'];
  context_manifest_json: string | null;
  error_code: string | null;
  attempt_count: number;
  submitted_at: string;
  created_at: string;
  updated_at: string;
}

const COLUMNS = `id, conversation_id, user_message_id, transcription_request_id, kind, status,
  audio_uri, audio_duration_seconds, transcript_confirmed_at, assistant_message_id, stance,
  context_manifest_json, error_code, attempt_count, submitted_at, created_at, updated_at`;

function mapRow(row: CoachingRequestRow): LocalCoachingRequest {
  return {
    id: row.id,
    conversationId: row.conversation_id,
    userMessageId: row.user_message_id,
    transcriptionRequestId: row.transcription_request_id,
    kind: row.kind,
    status: row.status,
    audioUri: row.audio_uri,
    audioDurationSeconds: row.audio_duration_seconds,
    transcriptConfirmedAt: row.transcript_confirmed_at,
    assistantMessageId: row.assistant_message_id,
    stance: row.stance,
    contextManifestJson: row.context_manifest_json,
    errorCode: row.error_code,
    attemptCount: row.attempt_count,
    submittedAt: row.submitted_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function params(request: LocalCoachingRequest) {
  return {
    $id: request.id,
    $conversationId: request.conversationId,
    $userMessageId: request.userMessageId,
    $transcriptionRequestId: request.transcriptionRequestId,
    $kind: request.kind,
    $status: request.status,
    $audioUri: request.audioUri,
    $audioDurationSeconds: request.audioDurationSeconds,
    $transcriptConfirmedAt: request.transcriptConfirmedAt,
    $assistantMessageId: request.assistantMessageId,
    $stance: request.stance,
    $contextManifestJson: request.contextManifestJson,
    $errorCode: request.errorCode,
    $attemptCount: request.attemptCount,
    $submittedAt: request.submittedAt,
    $createdAt: request.createdAt,
    $updatedAt: request.updatedAt,
  };
}

export async function insertCoachingRequest(
  transaction: RepositoryTransaction,
  request: LocalCoachingRequest,
  idempotencyId: string,
): Promise<void> {
  const values = params(request);
  if (!(await claimMutation(
    transaction,
    idempotencyId,
    'coaching-request',
    request.id,
    'insert',
    toDatabaseMutationPayload(values),
  ))) return;
  await transaction.runAsync(
    `INSERT INTO coaching_requests (${COLUMNS})
     VALUES ($id, $conversationId, $userMessageId, $transcriptionRequestId, $kind, $status,
       $audioUri, $audioDurationSeconds, $transcriptConfirmedAt, $assistantMessageId, $stance,
       $contextManifestJson, $errorCode, $attemptCount, $submittedAt, $createdAt, $updatedAt)`,
    values,
  );
}

export async function getCoachingRequest(
  database: RepositoryConnection,
  id: string,
): Promise<LocalCoachingRequest | null> {
  const row = await database.getFirstAsync<CoachingRequestRow>(
    `SELECT ${COLUMNS} FROM coaching_requests WHERE id = $id`,
    { $id: id },
  );
  return row === null ? null : mapRow(row);
}

export async function updateCoachingRequest(
  transaction: RepositoryTransaction,
  request: LocalCoachingRequest,
  idempotencyId: string,
): Promise<void> {
  const values = params(request);
  if (!(await claimMutation(
    transaction,
    idempotencyId,
    'coaching-request',
    request.id,
    'update',
    toDatabaseMutationPayload(values),
  ))) return;
  const result = await transaction.runAsync(
    `UPDATE coaching_requests SET conversation_id = $conversationId,
       user_message_id = $userMessageId, transcription_request_id = $transcriptionRequestId,
       kind = $kind, status = $status, audio_uri = $audioUri,
       audio_duration_seconds = $audioDurationSeconds,
       transcript_confirmed_at = $transcriptConfirmedAt,
       assistant_message_id = $assistantMessageId, stance = $stance,
       context_manifest_json = $contextManifestJson, error_code = $errorCode,
       attempt_count = $attemptCount, submitted_at = $submittedAt,
       created_at = $createdAt, updated_at = $updatedAt
     WHERE id = $id`,
    values,
  );
  requireExactlyOneAffectedRow(result, 'Cannot update missing coaching request');
}

export async function insertUsageReceipt(
  transaction: RepositoryTransaction,
  input: {
    id: string;
    requestId: string;
    receipt: UsageReceipt;
    recordedAt: string;
  },
  idempotencyId: string,
): Promise<void> {
  const payload = {
    id: input.id,
    requestId: input.requestId,
    receipt: input.receipt,
    recordedAt: input.recordedAt,
  };
  if (!(await claimMutation(
    transaction,
    idempotencyId,
    'usage-receipt',
    input.id,
    'insert',
    payload,
  ))) return;
  await transaction.runAsync(
    `INSERT INTO usage_receipts
       (id, request_id, provider, model, input_tokens, output_tokens, audio_seconds,
        estimated_cost_usd, recorded_at)
     VALUES ($id, $requestId, $provider, $model, $inputTokens, $outputTokens, $audioSeconds,
       $estimatedCostUsd, $recordedAt)`,
    {
      $id: input.id,
      $requestId: input.requestId,
      $provider: input.receipt.provider,
      $model: input.receipt.model,
      $inputTokens: input.receipt.inputTokens ?? null,
      $outputTokens: input.receipt.outputTokens ?? null,
      $audioSeconds: input.receipt.audioSeconds ?? null,
      $estimatedCostUsd: input.receipt.estimatedCostUsd,
      $recordedAt: input.recordedAt,
    },
  );
}
