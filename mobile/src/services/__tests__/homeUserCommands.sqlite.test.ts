import { createTestDatabase } from '../../repositories/__tests__/testDatabase';
import { createNotificationRepository } from '../../repositories/notificationRepository';
import { createHomeUserCommands } from '../homeUserCommands';

const NOW = '2026-08-26T09:00:00.000Z';

test('user task creation and weekly review persist without moving work', async () => {
  const database = createTestDatabase();
  const commands = createHomeUserCommands(database);
  await commands.createTask({
    id: 'task-user-1', title: '  Write update  ', sourceId: 'user',
    plannedWeek: '2026-08-24', now: NOW,
  });
  await commands.reviewWeek({
    id: 'week-2026-08-24', startsOn: '2026-08-24', endsOn: '2026-08-30',
    state: 'open', reviewedAt: null, closedAt: null,
  }, ['task-user-1', 'task-user-1'], 'snapshot-1', NOW);

  await expect(database.getFirstAsync<{ title: string; planned_week: string }>(
    'SELECT title, planned_week FROM work_records WHERE id = $id', { $id: 'task-user-1' },
  )).resolves.toEqual({ title: 'Write update', planned_week: '2026-08-24' });
  await expect(database.getFirstAsync<{ state: string }>(
    'SELECT state FROM weekly_periods WHERE id = $id', { $id: 'week-2026-08-24' },
  )).resolves.toEqual({ state: 'reviewed' });
  await expect(database.getFirstAsync<{ record_ids_json: string }>(
    'SELECT record_ids_json FROM weekly_period_snapshots WHERE id = $id', { $id: 'snapshot-1' },
  )).resolves.toEqual({ record_ids_json: '["task-user-1"]' });
  database.close();
});

test('notification read, snooze, and dismiss never mutate its source', async () => {
  const database = createTestDatabase();
  await database.withTransaction((transaction) => createNotificationRepository(database).insert(
    transaction,
    { id: 'notification-1', sourceType: 'work_record', sourceId: 'missing-source',
      groupingKey: 'work', readState: 'unread', disposition: 'active', snoozedUntil: null,
      createdAt: NOW },
    'seed-notification-1',
  ));
  const commands = createHomeUserCommands(database);
  await commands.updateNotification('notification-1', 'read');
  await commands.snoozeNotification('notification-1', '2026-08-27T09:00:00.000Z', NOW);
  await commands.updateNotification('notification-1', 'dismiss');

  await expect(database.getFirstAsync<{
    read_state: string; disposition: string; snoozed_until: string;
  }>('SELECT read_state, disposition, snoozed_until FROM local_notifications WHERE id = $id',
    { $id: 'notification-1' })).resolves.toEqual({
    read_state: 'read', disposition: 'dismissed', snoozed_until: '2026-08-27T09:00:00.000Z',
  });
  database.close();
});
