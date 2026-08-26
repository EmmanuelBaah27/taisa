import type { LocalNotification } from '@taisa/shared';

export interface NotificationPolicyResult {
  visible: LocalNotification[];
  groupCounts: Record<string, number>;
}

export function reconcileNotifications(
  notifications: readonly LocalNotification[],
  options: { now: string; mutedGroupingKeys: ReadonlySet<string> },
): NotificationPolicyResult {
  const eligible = notifications.filter((notification) => {
    if (options.mutedGroupingKeys.has(notification.groupingKey)) return false;
    if (notification.disposition === 'dismissed') return false;
    if (
      notification.disposition === 'snoozed'
      && notification.snoozedUntil !== null
      && notification.snoozedUntil > options.now
    ) return false;
    return true;
  });
  const groups = new Map<string, LocalNotification[]>();
  for (const notification of eligible) {
    const group = groups.get(notification.groupingKey) ?? [];
    group.push(notification);
    groups.set(notification.groupingKey, group);
  }
  const visible: LocalNotification[] = [];
  const groupCounts: Record<string, number> = {};
  for (const [key, group] of groups) {
    group.sort((left, right) =>
      right.createdAt.localeCompare(left.createdAt) || left.id.localeCompare(right.id));
    visible.push(group[0]);
    groupCounts[key] = group.length;
  }
  visible.sort((left, right) =>
    right.createdAt.localeCompare(left.createdAt) || left.id.localeCompare(right.id));
  return { visible, groupCounts };
}
