import type { RepositoryConnection, RepositoryTransaction } from '../db/types';
import { requireExactlyOneAffectedRow } from './mutationReceipt';

export interface LocalAudioCleanupEntry {
  audioUri: string;
  enqueuedAt: string;
  attemptCount: number;
  lastAttemptAt: string | null;
  lastErrorCode: string | null;
}

interface AudioCleanupRow {
  audio_uri: string;
  enqueued_at: string;
  attempt_count: number;
  last_attempt_at: string | null;
  last_error_code: string | null;
}

const MAX_CLEANUP_BATCH_SIZE = 50;
const CONTENT_FREE_ERROR_CODE = /^[A-Z][A-Z0-9_]{0,63}$/;

function requireCleanupLimit(limit: number): void {
  if (!Number.isInteger(limit) || limit <= 0 || limit > MAX_CLEANUP_BATCH_SIZE) {
    throw new TypeError(`Audio cleanup limit must be between 1 and ${MAX_CLEANUP_BATCH_SIZE}`);
  }
}

function mapRow(row: AudioCleanupRow): LocalAudioCleanupEntry {
  return {
    audioUri: row.audio_uri,
    enqueuedAt: row.enqueued_at,
    attemptCount: row.attempt_count,
    lastAttemptAt: row.last_attempt_at,
    lastErrorCode: row.last_error_code,
  };
}

export async function enqueueAudioCleanup(
  transaction: RepositoryTransaction,
  input: { audioUri: string; enqueuedAt: string },
): Promise<void> {
  await transaction.runAsync(
    `INSERT INTO audio_cleanup_queue (audio_uri, enqueued_at)
     VALUES ($audioUri, $enqueuedAt)
     ON CONFLICT(audio_uri) DO NOTHING`,
    { $audioUri: input.audioUri, $enqueuedAt: input.enqueuedAt },
  );
}

export async function listAudioCleanupQueue(
  database: RepositoryConnection,
  limit = 20,
): Promise<LocalAudioCleanupEntry[]> {
  requireCleanupLimit(limit);
  const rows = await database.getAllAsync<AudioCleanupRow>(
    `SELECT audio_uri, enqueued_at, attempt_count, last_attempt_at, last_error_code
     FROM audio_cleanup_queue
     ORDER BY enqueued_at ASC, audio_uri ASC
     LIMIT $limit`,
    { $limit: limit },
  );
  return rows.map(mapRow);
}

export async function listDeletableAudioCleanupQueue(
  database: RepositoryConnection,
  limit = 20,
): Promise<LocalAudioCleanupEntry[]> {
  requireCleanupLimit(limit);
  const rows = await database.getAllAsync<AudioCleanupRow>(
    `SELECT q.audio_uri, q.enqueued_at, q.attempt_count, q.last_attempt_at, q.last_error_code
     FROM audio_cleanup_queue q
     WHERE NOT EXISTS (
       SELECT 1 FROM coaching_requests r
       WHERE r.audio_uri = q.audio_uri
         AND r.status NOT IN ('completed', 'abandoned')
     )
     ORDER BY q.attempt_count ASC,
       COALESCE(q.last_attempt_at, q.enqueued_at) ASC,
       q.enqueued_at ASC,
       q.audio_uri ASC
     LIMIT $limit`,
    { $limit: limit },
  );
  return rows.map(mapRow);
}

export async function markAudioCleanupAttempt(
  transaction: RepositoryTransaction,
  input: { audioUri: string; attemptedAt: string; errorCode: string },
): Promise<void> {
  if (!CONTENT_FREE_ERROR_CODE.test(input.errorCode)) {
    throw new TypeError('Audio cleanup error code must be content-free');
  }
  const result = await transaction.runAsync(
    `UPDATE audio_cleanup_queue
     SET attempt_count = attempt_count + 1,
       last_attempt_at = $attemptedAt,
       last_error_code = $errorCode
     WHERE audio_uri = $audioUri`,
    {
      $audioUri: input.audioUri,
      $attemptedAt: input.attemptedAt,
      $errorCode: input.errorCode,
    },
  );
  requireExactlyOneAffectedRow(result, 'Cannot mark missing audio cleanup entry');
}

export async function removeAudioCleanup(
  transaction: RepositoryTransaction,
  audioUri: string,
): Promise<void> {
  await transaction.runAsync(
    'DELETE FROM audio_cleanup_queue WHERE audio_uri = $audioUri',
    { $audioUri: audioUri },
  );
}

export async function isAudioUriReferencedByActiveCoachingRequest(
  database: RepositoryConnection,
  audioUri: string,
): Promise<boolean> {
  const row = await database.getFirstAsync<{ referenced: 1 }>(
    `SELECT 1 AS referenced FROM coaching_requests
     WHERE audio_uri = $audioUri
       AND status NOT IN ('completed', 'abandoned')
     LIMIT 1`,
    { $audioUri: audioUri },
  );
  return row !== null;
}
