import type { RepositoryConnection, RepositoryTransaction } from '../db/types';

export interface BehaviorEvent {
  id: string;
  category: string;
  eventType: string;
  sourceId: string | null;
  occurredAt: string;
  expiresAt: string;
}

export interface BehaviorRepository {
  insertEvent(
    transaction: RepositoryTransaction,
    event: BehaviorEvent,
    idempotencyId: string,
  ): Promise<void>;
}

export function createBehaviorRepository(_database: RepositoryConnection): BehaviorRepository {
  return {
    async insertEvent(transaction, event, idempotencyId) {
      await transaction.runAsync(
        `INSERT INTO behavior_events
          (id, category, event_type, source_id, occurred_at, expires_at, idempotency_key)
         VALUES ($id, $category, $eventType, $sourceId, $occurredAt, $expiresAt, $idempotencyId)`,
        {
          $id: event.id, $category: event.category, $eventType: event.eventType,
          $sourceId: event.sourceId, $occurredAt: event.occurredAt,
          $expiresAt: event.expiresAt, $idempotencyId: idempotencyId,
        },
      );
    },
  };
}
