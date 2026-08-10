import * as Crypto from 'expo-crypto';
import * as SecureStore from 'expo-secure-store';
import type { CareerProfile, LocalCareerProfile } from '@taisa/shared';
import { create } from 'zustand';

import { openTaisaDatabase } from '../db/openDatabase';
import type { ExclusiveTransactionConnection } from '../db/types';
import { withRepositoryTransaction } from '../db/types';
import { listActions } from '../repositories/actionRepository';
import { listConversations } from '../repositories/conversationRepository';
import {
  getProfile,
  insertProfile,
  updateProfile as updateLocalProfile,
} from '../repositories/profileRepository';

interface CareerStoreDependencies {
  openDatabase(): Promise<ExclusiveTransactionConnection>;
  secureStore: Pick<typeof SecureStore, 'getItemAsync' | 'setItemAsync'>;
  now(): string;
  createId(): string;
}

interface CareerStore {
  profile: CareerProfile | null;
  userId: string | null;
  isOnboarded: boolean;
  isLoading: boolean;
  initUser: (deviceId: string, profileData: Partial<CareerProfile>) => Promise<void>;
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
  openDatabase: openTaisaDatabase,
  secureStore: SecureStore,
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
  return create<CareerStore>((set, get) => ({
    profile: null,
    userId: null,
    isOnboarded: false,
    isLoading: false,

    initUser: async (deviceId, profileData) => {
      set({ isLoading: true });
      try {
        const database = await dependencies.openDatabase();
        const timestamp = dependencies.now();
        const saved = await withRepositoryTransaction(database, async (transaction) => {
          const existing = await getProfile(transaction, deviceId);
          const next = localProfile(deviceId, profileData, timestamp, existing ?? undefined);
          if (existing === null) {
            await insertProfile(transaction, next, `profile:${dependencies.createId()}:insert`);
          } else {
            await updateLocalProfile(transaction, next, `profile:${dependencies.createId()}:update`);
          }
          return next;
        });
        await dependencies.secureStore.setItemAsync('userId', deviceId);
        set({
          profile: await viewProfile(database, saved),
          userId: deviceId,
          isOnboarded: true,
          isLoading: false,
        });
      } catch (error) {
        set({ isLoading: false });
        throw error;
      }
    },

    fetchProfile: async () => {
      const userId = await dependencies.secureStore.getItemAsync('userId');
      if (userId === null) throw new Error('Local profile is not initialized');
      const database = await dependencies.openDatabase();
      const stored = await getProfile(database, userId);
      if (stored === null) throw new Error('Local profile is not initialized');
      set({
        profile: await viewProfile(database, stored),
        userId,
        isOnboarded: true,
      });
    },

    updateProfile: async (data) => {
      const userId = get().userId ?? await dependencies.secureStore.getItemAsync('userId');
      if (userId === null) throw new Error('Local profile is not initialized');
      const database = await dependencies.openDatabase();
      const timestamp = dependencies.now();
      const saved = await withRepositoryTransaction(database, async (transaction) => {
        const existing = await getProfile(transaction, userId);
        if (existing === null) throw new Error('Local profile is not initialized');
        const next = localProfile(userId, data, timestamp, existing);
        await updateLocalProfile(transaction, next, `profile:${dependencies.createId()}:update`);
        return next;
      });
      set({ profile: await viewProfile(database, saved), userId });
    },

    setProfile: (profile) => set({ profile }),
  }));
}

export const useCareerStore = createCareerStore();
