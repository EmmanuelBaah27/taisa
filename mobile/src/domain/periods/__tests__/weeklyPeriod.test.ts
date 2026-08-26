import type { WorkRecord } from '@taisa/shared';

import {
  closeUnreviewedPeriod,
  createReviewedSnapshot,
  deriveWeeklyPeriod,
} from '../weeklyPeriod';

test('weekly periods use local Monday through Sunday boundaries', () => {
  expect(deriveWeeklyPeriod(new Date('2026-08-26T12:00:00Z'))).toMatchObject({
    id: 'week-2026-08-24', startsOn: '2026-08-24', endsOn: '2026-08-30', state: 'open',
  });
});

test('closing an unreviewed week changes only period state', () => {
  const period = deriveWeeklyPeriod(new Date('2026-08-26T12:00:00Z'));
  const record: WorkRecord = {
    id: 'task-1', kind: 'task', title: 'Send proposal', projectId: null,
    status: 'open', freshness: 'current', plannedWeek: period.startsOn, plannedDay: null,
    sourceId: 'conversation-1', revision: 1, createdAt: '2026-08-25T08:00:00Z',
    updatedAt: '2026-08-25T08:00:00Z', lastConfirmedAt: null,
  };

  const result = closeUnreviewedPeriod(period, '2026-08-31T08:00:00Z');

  expect(result.state).toBe('auto_closed_unreviewed');
  expect(record.plannedWeek).toBe('2026-08-24');
});

test('review creates an immutable record-id snapshot', () => {
  const period = deriveWeeklyPeriod(new Date('2026-08-26T12:00:00Z'));
  const recordIds = ['task-1', 'task-2'];

  const result = createReviewedSnapshot(
    period, recordIds, 'snapshot-1', '2026-08-30T18:00:00Z',
  );
  recordIds.push('task-3');

  expect(result.period).toMatchObject({ state: 'reviewed', reviewedAt: '2026-08-30T18:00:00Z' });
  expect(result.snapshot.recordIds).toEqual(['task-1', 'task-2']);
});
