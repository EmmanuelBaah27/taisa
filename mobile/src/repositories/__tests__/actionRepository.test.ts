import type { LocalAction } from '@taisa/shared';

import {
  getAction,
  insertAction,
  listActions,
  updateAction,
} from '../actionRepository';
import { createTestDatabase, LATER, NOW } from './testDatabase';

const action: LocalAction = {
  id: 'action-1',
  goalId: null,
  sourceMessageId: null,
  title: 'Document scope decisions after alignment meetings',
  description: null,
  lifecycle: 'open',
  priority: 'high',
  dueAt: null,
  supersedesId: null,
  createdAt: NOW,
  updatedAt: NOW,
  statusChangedAt: NOW,
};

describe('actionRepository', () => {
  test('creates, reads, updates, lists, and filters actions by lifecycle', async () => {
    const db = createTestDatabase();

    try {
      await db.withTransaction((tx) => insertAction(tx, action, 'action-create-1'));
      expect(await getAction(db, action.id)).toEqual(action);
      expect(await listActions(db, ['open'])).toEqual([action]);

      const completed: LocalAction = {
        ...action,
        lifecycle: 'completed',
        updatedAt: LATER,
        statusChangedAt: LATER,
      };
      await db.withTransaction((tx) => updateAction(tx, completed, 'action-update-1'));
      expect(await listActions(db, ['open'])).toEqual([]);
      expect(await listActions(db, ['completed'])).toEqual([completed]);
    } finally {
      db.close();
    }
  });
});
