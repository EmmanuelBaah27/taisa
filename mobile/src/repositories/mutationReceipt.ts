import type { RepositoryTransaction, SQLiteRunResultLike } from '../db/types';
import {
  MUTATION_FINGERPRINT_VERSION,
  fingerprintMutationPayload,
} from './mutationFingerprint';

interface MutationReceiptRow {
  entity_type: string;
  entity_id: string;
  operation: string;
  fingerprint_version: number;
  payload_digest: string;
}

export class IdempotencyConflictError extends Error {
  readonly code = 'IDEMPOTENCY_CONFLICT';

  constructor(readonly idempotencyId: string) {
    super(`Idempotency ID ${idempotencyId} was already used for another mutation`);
    this.name = 'IdempotencyConflictError';
  }
}

export class RepositoryMutationTargetMissingError extends Error {
  readonly code = 'REPOSITORY_MUTATION_TARGET_MISSING';

  constructor(message: string) {
    super(message);
    this.name = 'RepositoryMutationTargetMissingError';
  }
}

export function requireExactlyOneAffectedRow(
  result: SQLiteRunResultLike,
  missingTargetMessage: string,
): void {
  if (result.changes !== 1) {
    throw new RepositoryMutationTargetMissingError(missingTargetMessage);
  }
}

export async function claimMutation(
  transaction: RepositoryTransaction,
  idempotencyId: string,
  entityType: string,
  entityId: string,
  operation: string,
  payload: unknown,
): Promise<boolean> {
  if (idempotencyId.trim().length === 0) {
    throw new TypeError('Idempotency ID must not be empty');
  }

  const payloadDigest = await fingerprintMutationPayload(payload);
  const existing = await transaction.getFirstAsync<MutationReceiptRow>(
    `SELECT entity_type, entity_id, operation, fingerprint_version, payload_digest
       FROM mutation_receipts
      WHERE idempotency_id = $idempotencyId`,
    { $idempotencyId: idempotencyId },
  );
  if (existing !== null) {
    if (
      existing.entity_type === entityType &&
      existing.entity_id === entityId &&
      existing.operation === operation &&
      existing.fingerprint_version === MUTATION_FINGERPRINT_VERSION &&
      existing.payload_digest === payloadDigest
    ) {
      return false;
    }
    throw new IdempotencyConflictError(idempotencyId);
  }

  await transaction.runAsync(
    `INSERT INTO mutation_receipts
       (idempotency_id, entity_type, entity_id, operation, fingerprint_version, payload_digest)
     VALUES ($idempotencyId, $entityType, $entityId, $operation, $fingerprintVersion, $payloadDigest)`,
    {
      $idempotencyId: idempotencyId,
      $entityType: entityType,
      $entityId: entityId,
      $operation: operation,
      $fingerprintVersion: MUTATION_FINGERPRINT_VERSION,
      $payloadDigest: payloadDigest,
    },
  );
  return true;
}
