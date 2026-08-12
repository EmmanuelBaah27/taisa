import * as Crypto from 'expo-crypto';
import type { CareerProfile, LocalCareerProfile } from '@taisa/shared';
import { create } from 'zustand';

import { withTaisaDatabase } from '../db/openDatabase';
import type { ExclusiveTransactionConnection } from '../db/types';
import { withRepositoryTransaction } from '../db/types';
import { listActions } from '../repositories/actionRepository';
import { listConversations } from '../repositories/conversationRepository';
import {
  insertProfile,
  listProfiles,
  updateProfile as updateLocalProfile,
} from '../repositories/profileRepository';

interface CareerStoreDependencies {
  openDatabase?: () => Promise<ExclusiveTransactionConnection>;
  withDatabase?: <T>(work: (database: ExclusiveTransactionConnection) => Promise<T>) => Promise<T>;
  // Accepted for compatibility with injected store tests; profile identity is never read from it.
  secureStore?: unknown;
  now(): string;
  createId(): string;
}

export class LocalProfileArchiveError extends Error {
  readonly code = 'LOCAL_PROFILE_ARCHIVE';

  constructor(readonly reason: 'missing' | 'ambiguous') {
    super(reason === 'missing'
      ? 'The local profile archive is empty.'
      : 'The local profile archive contains more than one profile.');
    this.name = 'LocalProfileArchiveError';
  }
}

interface CareerStore {
  profile: CareerProfile | null;
  userId: string | null;
  isOnboarded: boolean;
  isLoading: boolean;
  initUser: (profileId: string, profileData: Partial<CareerProfile>) => Promise<void>;
  fetchProfile: () => Promise<void>;
  updateProfile: (data: Partial<CareerProfile>) => Promise<void>;
  setProfile: (profile: CareerProfile) => void;
}

function localProfile(
  id: string,
  data: Partial<CareerProfile>,
  timestamp: string,
  existing?: LocalCareerProfile,
): LocalCareerProfile {
  return {
    id,
    currentRole: data.currentRole ?? existing?.currentRole ?? null,
    currentCompany: data.currentCompany !== undefined
      ? data.currentCompany
      : existing?.currentCompany ?? null,
    industry: data.industry ?? existing?.industry ?? null,
    yearsOfExperience: data.yearsOfExperience ?? existing?.yearsOfExperience ?? null,
    careerStage: data.careerStage ?? existing?.careerStage ?? null,
    currentFocusArea: data.currentFocusArea ?? existing?.currentFocusArea ?? null,
    shortTermGoal: data.shortTermGoal ?? existing?.shortTermGoal ?? null,
    longTermGoal: data.longTermGoal ?? existing?.longTermGoal ?? null,
    coachingStyle: data.coachingStyle ?? existing?.coachingStyle ?? null,
    accountabilityLevel: data.accountabilityLevel ?? existing?.accountabilityLevel ?? null,
    reminderTimes: data.reminderTimes ?? existing?.reminderTimes ?? [],
    createdAt: existing?.createdAt ?? timestamp,
    updatedAt: timestamp,
  };
}

async function viewProfile(
  database: ExclusiveTransactionConnection,
  profile: LocalCareerProfile,
): Promise<CareerProfile> {
  const [conversations, openActions] = await Promise.all([
    listConversations(database),
    listActions(database, ['open']),
  ]);
  return {
    id: profile.id,
    userId: profile.id,
    createdAt: profile.createdAt,
    updatedAt: profile.updatedAt,
    currentRole: profile.currentRole ?? '',
    currentCompany: profile.currentCompany,
    industry: profile.industry ?? '',
    yearsOfExperience: profile.yearsOfExperience ?? 0,
    careerStage: profile.careerStage ?? 'mid',
    shortTermGoal: profile.shortTermGoal ?? '',
    longTermGoal: profile.longTermGoal ?? '',
    currentFocusArea: profile.currentFocusArea ?? '',
    coachingStyle: profile.coachingStyle ?? 'socratic',
    accountabilityLevel: profile.accountabilityLevel ?? 'moderate',
    reminderTimes: [...profile.reminderTimes],
    dominantThemes: [],
    growthTrajectory: 'steady',
    openActionItemCount: openActions.length,
    totalEntryCount: conversations.length,
    lastEntryAt: conversations[0]?.updatedAt ?? null,
  };
}

const nativeDependencies: CareerStoreDependencies = {
  withDatabase: withTaisaDatabase,
  now: () => new Date().toISOString(),
  createId: () => Crypto.randomUUID(),
};

export function createCareerStore(
  supplied: Omit<CareerStoreDependencies, 'createId'> & Partial<Pick<CareerStoreDependencies, 'createId'>> = nativeDependencies,
) {
  const dependencies: CareerStoreDependencies = {
    ...supplied,
    createId: supplied.createId ?? (() => Crypto.randomUUID()),
  };
  function withDatabase<T>(
    work: (database: ExclusiveTransactionConnection) => Promise<T>,
  ): Promise<T> {
    if (dependencies.withDatabase !== undefined) return dependencies.withDatabase(work);
    if (dependencies.openDatabase !== undefined) {
      return dependencies.openDatabase().then(work);
    }
    throw new Error('Career store database boundary is unavailable');
  }
  return create<CareerStore>((set) => ({
    profile: null,
    userId: null,
    isOnboarded: false,
    isLoading: false,

    initUser: async (profileId, profileData) => {
      set({ isLoading: true });
      try {
        const state = await withDatabase(async (database) => {
          const timestamp = dependencies.now();
          const saved = await withRepositoryTransaction(database, async (transaction) => {
            const profiles = await listProfiles(transaction);
            if (profiles.length > 1) throw new LocalProfileArchiveError('ambiguous');
            const existing = profiles[0] ?? null;
            const next = localProfile(existing?.id ?? profileId, profileData, timestamp, existing ?? undefined);
            if (existing === null) {
              await insertProfile(transaction, next, `profile:${dependencies.createId()}:insert`);
            } else {
              await updateLocalProfile(transaction, next, `profile:${dependencies.createId()}:update`);
            }
            return next;
          });
          return { profile: await viewProfile(database, saved), userId: saved.id };
        });
        set({
          ...state,
          isOnboarded: true,
          isLoading: false,
        });
      } catch (error) {
        set({ isLoading: false });
        throw error;
      }
    },

    fetchProfile: async () => {
      const state = await withDatabase(async (database) => {
        const profiles = await listProfiles(database);
        if (profiles.length === 0) throw new LocalProfileArchiveError('missing');
        if (profiles.length > 1) throw new LocalProfileArchiveError('ambiguous');
        const stored = profiles[0];
        return { profile: await viewProfile(database, stored), userId: stored.id };
      });
      set({
        ...state,
        isOnboarded: true,
      });
    },

    updateProfile: async (data) => {
      const state = await withDatabase(async (database) => {
        const timestamp = dependencies.now();
        const saved = await withRepositoryTransaction(database, async (transaction) => {
          const profiles = await listProfiles(transaction);
          if (profiles.length === 0) throw new LocalProfileArchiveError('missing');
          if (profiles.length > 1) throw new LocalProfileArchiveError('ambiguous');
          const existing = profiles[0];
          const next = localProfile(existing.id, data, timestamp, existing);
          await updateLocalProfile(transaction, next, `profile:${dependencies.createId()}:update`);
          return next;
        });
        return { profile: await viewProfile(database, saved), userId: saved.id };
      });
      set(state);
    },

    setProfile: (profile) => set({ profile }),
  }));
}

export const useCareerStore = createCareerStore();
