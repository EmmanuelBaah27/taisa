import type { WeeklyPeriod } from '@taisa/shared';

import type { ExclusiveTransactionConnection } from '../db/types';
import { withRepositoryTransaction } from '../db/types';
import { createReviewedSnapshot } from '../domain/periods/weeklyPeriod';
import { createPeriodRepository } from '../repositories/periodRepository';
import { createWorkRepository } from '../repositories/workRepository';
import type { CreateTaskInput } from '../stores/homeStore';

export function createHomeUserCommands(database: ExclusiveTransactionConnection) {
  return {
    async createTask(input: CreateTaskInput): Promise<void> {
      const title = input.title.trim();
      if (title.length === 0 || title.length > 500) throw new Error('Invalid task title');
      await withRepositoryTransaction(database, (transaction) =>
        createWorkRepository(transaction).insert(transaction, {
          id: input.id, kind: 'task', title, projectId: null, status: 'open',
          freshness: 'current', plannedWeek: input.plannedWeek, plannedDay: null,
          sourceId: input.sourceId, revision: 1, createdAt: input.now, updatedAt: input.now,
          lastConfirmedAt: input.now,
        }, input.id));
    },
    async reviewWeek(
      period: WeeklyPeriod,
      recordIds: string[],
      snapshotId: string,
      now: string,
    ): Promise<void> {
      const reviewed = createReviewedSnapshot(period, [...new Set(recordIds)], snapshotId, now);
      await withRepositoryTransaction(database, async (transaction) => {
        const periods = createPeriodRepository(transaction);
        await periods.putPeriod(transaction, reviewed.period);
        await periods.insertSnapshot(transaction, reviewed.snapshot);
      });
    },
    async updateNotification(id: string, change: 'read' | 'dismiss'): Promise<void> {
      const assignment = change === 'read'
        ? "read_state = 'read'"
        : "disposition = 'dismissed'";
      await withRepositoryTransaction(database, async (transaction) => {
        const result = await transaction.runAsync(
          `UPDATE local_notifications SET ${assignment} WHERE id = $id`, { $id: id },
        );
        if (result.changes !== 1) throw new Error('Notification is unavailable');
      });
    },
    async snoozeNotification(id: string, until: string, now: string): Promise<void> {
      if (!Number.isFinite(Date.parse(until)) || until <= now) throw new Error('Invalid snooze time');
      await withRepositoryTransaction(database, async (transaction) => {
        const result = await transaction.runAsync(
          `UPDATE local_notifications SET disposition = 'snoozed', snoozed_until = $until
           WHERE id = $id`, { $id: id, $until: until },
        );
        if (result.changes !== 1) throw new Error('Notification is unavailable');
      });
    },
  };
}
