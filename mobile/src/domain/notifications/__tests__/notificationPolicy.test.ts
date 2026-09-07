import type { LocalNotification } from '@taisa/shared';

import { reconcileNotifications } from '../notificationPolicy';

function notification(overrides: Partial<LocalNotification>): LocalNotification {
  return {
    id: 'notification-1', sourceType: 'proposal', sourceId: 'proposal-1',
    groupingKey: 'proposal-review', readState: 'unread', disposition: 'active',
    snoozedUntil: null, createdAt: '2026-08-25T08:00:00Z', ...overrides,
  };
}

test('notifications group by key and keep the newest active source', () => {
  const result = reconcileNotifications([
    notification({ id: 'older', createdAt: '2026-08-25T08:00:00Z' }),
    notification({ id: 'newer', sourceId: 'proposal-2', createdAt: '2026-08-25T09:00:00Z' }),
  ], { now: '2026-08-26T08:00:00Z', mutedGroupingKeys: new Set() });

  expect(result.visible.map((item) => item.id)).toEqual(['newer']);
  expect(result.groupCounts).toEqual({ 'proposal-review': 2 });
});

test('dismissed, snoozed, and muted notifications are silent without changing source state', () => {
  const source = { id: 'proposal-1', resolution: 'unapplied' };
  const result = reconcileNotifications([
    notification({ id: 'dismissed', disposition: 'dismissed' }),
    notification({ id: 'snoozed', disposition: 'snoozed', snoozedUntil: '2026-08-27T08:00:00Z' }),
    notification({ id: 'muted', groupingKey: 'weekly-review' }),
  ], { now: '2026-08-26T08:00:00Z', mutedGroupingKeys: new Set(['weekly-review']) });

  expect(result.visible).toEqual([]);
  expect(source).toEqual({ id: 'proposal-1', resolution: 'unapplied' });
});
