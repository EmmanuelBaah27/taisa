import { create } from 'zustand';
import * as SecureStore from 'expo-secure-store';
import type { CareerProfile } from '@taisa/shared';
import api from '../services/api';

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

export const useCareerStore = create<CareerStore>((set, get) => ({
  profile: null,
  userId: null,
  isOnboarded: false,
  isLoading: false,

  initUser: async (deviceId, profileData) => {
    set({ isLoading: true });
    try {
      const res = await api.post('/profile/init', { deviceId, ...profileData });
      const profile: CareerProfile = res.data.data;
      await SecureStore.setItemAsync('userId', deviceId);
      set({ profile, userId: deviceId, isOnboarded: true, isLoading: false });
    } catch (e) {
      set({ isLoading: false });
      throw e;
    }
  },

  fetchProfile: async () => {
    const [res, storedId] = await Promise.all([
      api.get('/profile'),
      SecureStore.getItemAsync('userId'),
    ]);
    set({ profile: res.data.data, userId: storedId });
  },

  updateProfile: async (data) => {
    const res = await api.put('/profile', data);
    set({ profile: res.data.data });
  },

  setProfile: (profile) => set({ profile }),
}));
