import type { LocalGoal, LocalMilestone } from '@taisa/shared';

import {
  deleteGoal,
  getGoal,
  getMilestone,
  insertGoal,
  insertMilestone,
  listGoals,
  listMilestones,
  supersedeGoal,
  updateGoal,
  updateMilestone,
} from '../goalRepository';
import { createTestDatabase, LATER, NOW } from './testDatabase';

const managementGoal: LocalGoal = {
  id: 'goal-management',
  title: 'Explore people management',
  description: 'Run one management experiment.',
  lifecycle: 'active',
  priority: 'medium',
  progressPercent: 25,
  targetDate: null,
  sourceMessageId: null,
  supersedesId: null,
  createdAt: NOW,
  updatedAt: NOW,
  statusChangedAt: NOW,
};

describe('goalRepository', () => {
  test('creates, reads, updates, lists, and supersedes goals while preserving history', async () => {
    const db = createTestDatabase();

    try {
      await db.withTransaction((tx) => insertGoal(tx, managementGoal, 'goal-create-1'));
      await db.withTransaction((tx) =>
        updateGoal(tx, { ...managementGoal, progressPercent: 40, updatedAt: LATER }, 'goal-update-1'),
      );

      const staffGoal: LocalGoal = {
        ...managementGoal,
        id: 'goal-staff',
        title: 'Grow toward Staff Designer',
        lifecycle: 'active',
        progressPercent: 0,
        supersedesId: managementGoal.id,
        createdAt: LATER,
        updatedAt: LATER,
        statusChangedAt: LATER,
      };
      await db.withTransaction((tx) =>
        supersedeGoal(tx, managementGoal.id, staffGoal, 'goal-supersede-1'),
      );

      expect((await getGoal(db, managementGoal.id))?.lifecycle).toBe('superseded');
      expect(await getGoal(db, staffGoal.id)).toEqual(staffGoal);
      expect(await listGoals(db, ['active'])).toEqual([staffGoal]);
      expect((await listGoals(db, ['superseded']))[0]?.id).toBe(managementGoal.id);
    } finally {
      db.close();
    }
  });

  test('maps milestone CRUD and cascades milestones when a goal is deleted', async () => {
    const db = createTestDatabase();
    const milestone: LocalMilestone = {
      id: 'milestone-1',
      goalId: managementGoal.id,
      title: 'Lead a roadmap workshop',
      lifecycle: 'pending',
      createdAt: NOW,
      updatedAt: NOW,
      completedAt: null,
    };

    try {
      await db.withTransaction((tx) => insertGoal(tx, managementGoal, 'goal-create-1'));
      await db.withTransaction((tx) => insertMilestone(tx, milestone, 'milestone-create-1'));
      expect(await getMilestone(db, milestone.id)).toEqual(milestone);
      expect(await listMilestones(db, managementGoal.id)).toEqual([milestone]);

      const completed: LocalMilestone = {
        ...milestone,
        lifecycle: 'completed',
        updatedAt: LATER,
        completedAt: LATER,
      };
      await db.withTransaction((tx) =>
        updateMilestone(tx, completed, 'milestone-update-1'),
      );
      expect(await getMilestone(db, milestone.id)).toEqual(completed);

      await db.withTransaction((tx) => deleteGoal(tx, managementGoal.id, 'goal-delete-1'));
      expect(await getGoal(db, managementGoal.id)).toBeNull();
      expect(await getMilestone(db, milestone.id)).toBeNull();
    } finally {
      db.close();
    }
  });

  test('rolls back both the receipt and successor when the superseded goal is missing', async () => {
    const db = createTestDatabase();
    const staffGoal: LocalGoal = {
      ...managementGoal,
      id: 'goal-staff',
      title: 'Grow toward Staff Designer',
      supersedesId: managementGoal.id,
    };

    try {
      await expect(
        db.withTransaction((tx) =>
          supersedeGoal(tx, managementGoal.id, staffGoal, 'goal-supersede-retry'),
        ),
      ).rejects.toThrow('Cannot supersede a missing goal');
      expect(await getGoal(db, staffGoal.id)).toBeNull();

      await db.withTransaction((tx) => insertGoal(tx, managementGoal, 'goal-create-1'));
      await db.withTransaction((tx) =>
        supersedeGoal(tx, managementGoal.id, staffGoal, 'goal-supersede-retry'),
      );
      expect(await getGoal(db, staffGoal.id)).toEqual(staffGoal);
    } finally {
      db.close();
    }
  });
});
