import type { Insight, WeeklyPeriod, WorkRecord } from '@taisa/shared';

import { selectHome } from '../selectHome';

const period: WeeklyPeriod = {
  id: 'week-2026-08-24', startsOn: '2026-08-24', endsOn: '2026-08-30',
  state: 'open', reviewedAt: null, closedAt: null,
};

function task(id: string, plannedWeek: string | null, updatedAt: string): WorkRecord {
  return {
    id, kind: 'task', title: id, projectId: null, status: 'open', freshness: 'current',
    plannedWeek, plannedDay: null, sourceId: 'conversation-1', revision: 1,
    createdAt: updatedAt, updatedAt, lastConfirmedAt: null,
  };
}

function insight(id: string, freshness: Insight['freshness']): Insight {
  return {
    id, kind: 'operational', title: id, body: id, freshness, evidence: [],
    createdAt: '2026-08-25T08:00:00Z', updatedAt: '2026-08-25T08:00:00Z',
  };
}

test('Home has stable local section order and deduplicated Keep moving', () => {
  const thisWeek = task('task-week', period.startsOn, '2026-08-25T08:00:00Z');
  const unplanned = task('task-unplanned', null, '2026-08-26T08:00:00Z');

  const view = selectHome({
    period,
    records: [thisWeek, unplanned, thisWeek],
    insights: [insight('insight-current', 'current')],
    pendingProposalCount: 2,
  });

  expect(view.sections.map((section) => section.kind)).toEqual([
    'lead_insight', 'this_week', 'carry_over', 'updates_to_review',
    'weekly_review', 'organize_week', 'keep_moving', 'conversation_input',
  ]);
  expect(view.keepMoving.map((record) => record.id)).toEqual(['task-unplanned']);
  expect(view.pendingProposalCount).toBe(2);
});

test('Home excludes stale and contradictory lead insights', () => {
  const view = selectHome({
    period,
    records: [],
    insights: [insight('stale', 'stale'), insight('contradictory', 'contradictory')],
    pendingProposalCount: 0,
  });

  expect(view.leadInsight).toBeNull();
});
