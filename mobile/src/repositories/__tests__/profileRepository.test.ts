import type { LocalCareerProfile } from '@taisa/shared';

import {
  IdempotencyConflictError,
  getProfile,
  insertProfile,
  listProfiles,
  updateProfile,
} from '../profileRepository';
import { createTestDatabase, LATER, NOW } from './testDatabase';

const profile: LocalCareerProfile = {
  id: 'device-1',
  currentRole: 'Product Designer',
  currentCompany: 'Example Co',
  industry: 'Technology',
  yearsOfExperience: 7,
  careerStage: 'senior',
  currentFocusArea: 'Stakeholder influence',
  shortTermGoal: 'Lead roadmap framing',
  longTermGoal: 'Become a Staff Designer',
  coachingStyle: 'socratic',
  accountabilityLevel: 'moderate',
  reminderTimes: ['15:00'],
  createdAt: NOW,
  updatedAt: NOW,
};

describe('profileRepository', () => {
  test('creates, reads, updates, and lists profiles with durable idempotency', async () => {
    const db = createTestDatabase();

    try {
      await db.withTransaction((tx) => insertProfile(tx, profile, 'profile-create-1'));
      await db.withTransaction((tx) =>
        insertProfile(tx, { ...profile, currentRole: 'Ignored duplicate' }, 'profile-create-1'),
      );

      expect(await getProfile(db, profile.id)).toEqual(profile);
      expect(await listProfiles(db)).toEqual([profile]);

      const updated = { ...profile, currentRole: 'Lead Product Designer', updatedAt: LATER };
      await db.withTransaction((tx) => updateProfile(tx, updated, 'profile-update-1'));
      await db.withTransaction((tx) =>
        updateProfile(tx, { ...updated, currentRole: 'Ignored retry' }, 'profile-update-1'),
      );
      expect(await getProfile(db, profile.id)).toEqual(updated);

      await expect(
        db.withTransaction((tx) => insertProfile(tx, profile, 'profile-update-1')),
      ).rejects.toBeInstanceOf(IdempotencyConflictError);
    } finally {
      db.close();
    }
  });
});
