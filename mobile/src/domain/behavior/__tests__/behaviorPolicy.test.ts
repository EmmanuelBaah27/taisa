import {
  buildBehaviorSubmissionPreview,
  reconcileBehaviorEvents,
  selectBehaviorDeletion,
  type BehavioralEvent,
} from '../behaviorPolicy';

const events: BehavioralEvent[] = [
  {
    id: 'correction-old', category: 'correction', eventType: 'proposal_rejected',
    occurredAt: '2026-05-01T08:00:00Z', expiresAt: '2026-07-30T08:00:00Z',
  },
  {
    id: 'correction-new', category: 'correction', eventType: 'undo',
    occurredAt: '2026-08-25T08:00:00Z', expiresAt: '2026-11-23T08:00:00Z',
  },
  {
    id: 'timing-new', category: 'timing', eventType: 'review_opened',
    occurredAt: '2026-08-25T09:00:00Z', expiresAt: '2026-11-23T09:00:00Z',
  },
];

test('reconciliation expires raw events and honors paused categories', () => {
  expect(reconcileBehaviorEvents(events, {
    now: '2026-08-26T08:00:00Z', pausedCategories: new Set(['timing']),
  })).toEqual({
    retained: [events[1]],
    deleteIds: ['correction-old'],
  });
});

test('category deletion is independent and all deletion is explicit', () => {
  expect(selectBehaviorDeletion(events, 'correction')).toEqual(['correction-old', 'correction-new']);
  expect(selectBehaviorDeletion(events, 'all')).toEqual([
    'correction-old', 'correction-new', 'timing-new',
  ]);
});

test('external preview contains category counts, never event content or identity labels', () => {
  expect(buildBehaviorSubmissionPreview(events.slice(1), {
    startsAt: '2026-08-24T00:00:00Z', endsAt: '2026-08-30T23:59:59Z',
  })).toEqual({
    period: { startsAt: '2026-08-24T00:00:00Z', endsAt: '2026-08-30T23:59:59Z' },
    categories: [{ category: 'correction', count: 1 }, { category: 'timing', count: 1 }],
  });
});
