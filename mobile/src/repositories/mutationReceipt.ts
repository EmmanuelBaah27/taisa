import type { RepositoryTransaction } from '../db/types';

interface MutationReceiptRow {
  entity_type: string;
  entity_id: string;
  operation: string;
}

export class IdempotencyConflictError extends Error {
  readonly code = 'IDEMPOTENCY_CONFLICT';

  constructor(readonly idempotencyId: string) {
    super(`Idempotency ID ${idempotencyId} was already used for another mutation`);
    this.name = 'IdempotencyConflictError';
  }
}

export async function claimMutation(
  transaction: RepositoryTransaction,
  idempotencyId: string,
  entityType: string,
  entityId: string,
  operation: string,
): Promise<boolean> {
  if (idempotencyId.trim().length === 0) {
    throw new TypeError('Idempotency ID must not be empty');
  }

  const existing = await transaction.getFirstAsync<MutationReceiptRow>(
    `SELECT entity_type, entity_id, operation
       FROM mutation_receipts
      WHERE idempotency_id = $idempotencyId`,
    { $idempotencyId: idempotencyId },
  );
  if (existing !== null) {
    if (
      existing.entity_type === entityType &&
      existing.entity_id === entityId &&
      existing.operation === operation
    ) {
      return false;
    }
    throw new IdempotencyConflictError(idempotencyId);
  }

  await transaction.runAsync(
    `INSERT INTO mutation_receipts (idempotency_id, entity_type, entity_id, operation)
     VALUES ($idempotencyId, $entityType, $entityId, $operation)`,
    {
      $idempotencyId: idempotencyId,
      $entityType: entityType,
      $entityId: entityId,
      $operation: operation,
    },
  );
  return true;
}
