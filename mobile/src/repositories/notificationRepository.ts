import type { LocalNotification } from '@taisa/shared';

import type { RepositoryConnection, RepositoryTransaction } from '../db/types';

export interface NotificationRepository {
  insert(
    transaction: RepositoryTransaction,
    notification: LocalNotification,
    idempotencyId: string,
  ): Promise<void>;
}

export function createNotificationRepository(_database: RepositoryConnection): NotificationRepository {
  return {
    async insert(transaction, notification, idempotencyId) {
      await transaction.runAsync(
        `INSERT INTO local_notifications
          (id, source_type, source_id, grouping_key, read_state, disposition,
           snoozed_until, created_at, idempotency_key)
         VALUES ($id, $sourceType, $sourceId, $groupingKey, $readState, $disposition,
           $snoozedUntil, $createdAt, $idempotencyId)`,
        {
          $id: notification.id,
          $sourceType: notification.sourceType,
          $sourceId: notification.sourceId,
          $groupingKey: notification.groupingKey,
          $readState: notification.readState,
          $disposition: notification.disposition,
          $snoozedUntil: notification.snoozedUntil,
          $createdAt: notification.createdAt,
          $idempotencyId: idempotencyId,
        },
      );
    },
  };
}
