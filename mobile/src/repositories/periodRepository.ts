import type { WeeklyPeriod, WeeklyPeriodSnapshot } from '@taisa/shared';

import type { RepositoryConnection, RepositoryTransaction } from '../db/types';

export interface PeriodRepository {
  putPeriod(transaction: RepositoryTransaction, period: WeeklyPeriod): Promise<void>;
  insertSnapshot(transaction: RepositoryTransaction, snapshot: WeeklyPeriodSnapshot): Promise<void>;
}

export function createPeriodRepository(_database: RepositoryConnection): PeriodRepository {
  return {
    async putPeriod(transaction, period) {
      await transaction.runAsync(
        `INSERT INTO weekly_periods (id, starts_on, ends_on, state, reviewed_at, closed_at)
         VALUES ($id, $startsOn, $endsOn, $state, $reviewedAt, $closedAt)
         ON CONFLICT(id) DO UPDATE SET state = excluded.state,
           reviewed_at = excluded.reviewed_at, closed_at = excluded.closed_at`,
        {
          $id: period.id, $startsOn: period.startsOn, $endsOn: period.endsOn,
          $state: period.state, $reviewedAt: period.reviewedAt, $closedAt: period.closedAt,
        },
      );
    },
    async insertSnapshot(transaction, snapshot) {
      await transaction.runAsync(
        `INSERT INTO weekly_period_snapshots (id, period_id, record_ids_json, created_at)
         VALUES ($id, $periodId, $recordIdsJson, $createdAt)`,
        {
          $id: snapshot.id, $periodId: snapshot.periodId,
          $recordIdsJson: JSON.stringify(snapshot.recordIds), $createdAt: snapshot.createdAt,
        },
      );
    },
  };
}
