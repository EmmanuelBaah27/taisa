import type { WeeklyPeriod, WeeklyPeriodSnapshot } from '@taisa/shared';

function localDate(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

export function deriveWeeklyPeriod(now: Date): WeeklyPeriod {
  if (!Number.isFinite(now.getTime())) throw new TypeError('Invalid period date');
  const starts = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const weekday = starts.getDay();
  starts.setDate(starts.getDate() - (weekday === 0 ? 6 : weekday - 1));
  const ends = new Date(starts);
  ends.setDate(ends.getDate() + 6);
  const startsOn = localDate(starts);
  return {
    id: `week-${startsOn}`,
    startsOn,
    endsOn: localDate(ends),
    state: 'open',
    reviewedAt: null,
    closedAt: null,
  };
}

export function closeUnreviewedPeriod(period: WeeklyPeriod, closedAt: string): WeeklyPeriod {
  if (period.state !== 'open') return period;
  return { ...period, state: 'auto_closed_unreviewed', closedAt };
}

export function createReviewedSnapshot(
  period: WeeklyPeriod,
  recordIds: readonly string[],
  snapshotId: string,
  reviewedAt: string,
): { period: WeeklyPeriod; snapshot: WeeklyPeriodSnapshot } {
  return {
    period: { ...period, state: 'reviewed', reviewedAt, closedAt: period.closedAt ?? reviewedAt },
    snapshot: {
      id: snapshotId,
      periodId: period.id,
      recordIds: [...recordIds],
      createdAt: reviewedAt,
    },
  };
}
