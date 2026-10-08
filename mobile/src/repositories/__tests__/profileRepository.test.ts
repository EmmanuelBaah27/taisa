import type { LocalCareerProfile } from '@taisa/shared';

import { withRepositoryTransaction } from '../../db/types';
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
        insertProfile(tx, profile, 'profile-create-1'),
      );
      await expect(
        db.withTransaction((tx) =>
          insertProfile(tx, { ...profile, currentRole: 'Changed retry' }, 'profile-create-1'),
        ),
      ).rejects.toBeInstanceOf(IdempotencyConflictError);

      expect(await getProfile(db, profile.id)).toEqual(profile);
      expect(await listProfiles(db)).toEqual([profile]);

      const receipt = await db.getFirstAsync<{
        fingerprint_version: number;
        payload_digest: string;
      }>(
        `SELECT fingerprint_version, payload_digest FROM mutation_receipts
         WHERE idempotency_id = $id`,
        { $id: 'profile-create-1' },
      );
      expect(receipt).toEqual({
        fingerprint_version: 1,
        payload_digest: expect.stringMatching(/^[0-9a-f]{64}$/),
      });

      const updated = { ...profile, currentRole: 'Lead Product Designer', updatedAt: LATER };
      await db.withTransaction((tx) => updateProfile(tx, updated, 'profile-update-1'));
      await db.withTransaction((tx) => updateProfile(tx, updated, 'profile-update-1'));
      expect(await getProfile(db, profile.id)).toEqual(updated);

      await expect(
        db.withTransaction((tx) => insertProfile(tx, profile, 'profile-update-1')),
      ).rejects.toBeInstanceOf(IdempotencyConflictError);
    } finally {
      db.close();
    }
  });

  test('a missing profile update rolls back its receipt so the same mutation can be retried', async () => {
    const db = createTestDatabase();
    const updated = { ...profile, currentRole: 'Lead Product Designer', updatedAt: LATER };

    try {
      await expect(
        db.withTransaction((tx) => updateProfile(tx, updated, 'profile-update-retry')),
      ).rejects.toThrow('Cannot update missing profile');

      await db.withTransaction((tx) => insertProfile(tx, profile, 'profile-create-1'));
      await db.withTransaction((tx) => updateProfile(tx, updated, 'profile-update-retry'));
      expect(await getProfile(db, profile.id)).toEqual(updated);
    } finally {
      db.close();
    }
  });

  test('runs repository mutations through the exclusive branded transaction helper', async () => {
    const db = createTestDatabase();

    try {
      const id = await withRepositoryTransaction(db, async (transaction) => {
        await insertProfile(transaction, profile, 'profile-create-branded');
        return profile.id;
      });

      expect(id).toBe(profile.id);
      expect(await getProfile(db, profile.id)).toEqual(profile);
    } finally {
      db.close();
    }
  });
});
