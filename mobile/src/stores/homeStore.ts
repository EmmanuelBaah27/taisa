import type { HomeView, Insight, WeeklyPeriod, WorkRecord } from '@taisa/shared';
import { create } from 'zustand';

import { selectHome } from '../domain/home/selectHome';
import { withTaisaDatabase } from '../db/openDatabase';
import { loadHomeSnapshot } from '../repositories/homeSnapshotRepository';

export interface HomeSnapshot {
  period: WeeklyPeriod;
  records: WorkRecord[];
  insights: Insight[];
  pendingProposalCount: number;
}

export interface HomeStoreDependencies {
  load(now: string): Promise<HomeSnapshot>;
}

export interface HomeStoreState {
  view: HomeView | null;
  hydratedAt: string | null;
  isHydrating: boolean;
  error: string | null;
  hydrate(now: string): Promise<void>;
  clearError(): void;
  clearForAuthorityReplacement(): void;
}

export function createHomeStore(dependencies: HomeStoreDependencies) {
  let generation = 0;
  return create<HomeStoreState>((set) => ({
    view: null,
    hydratedAt: null,
    isHydrating: false,
    error: null,
    hydrate: async (now) => {
      const current = generation += 1;
      set({ isHydrating: true, error: null });
      try {
        const snapshot = await dependencies.load(now);
        if (current !== generation) return;
        set({
          view: selectHome(snapshot),
          hydratedAt: now,
          isHydrating: false,
        });
      } catch {
        if (current !== generation) return;
        set({
          view: null,
          hydratedAt: null,
          isHydrating: false,
          error: 'The local Home archive is unavailable.',
        });
      }
    },
    clearError: () => set({ error: null }),
    clearForAuthorityReplacement: () => {
      generation += 1;
      set({ view: null, hydratedAt: null, isHydrating: false, error: null });
    },
  }));
}

export const useHomeStore = createHomeStore({
  load: (now) => withTaisaDatabase((database) => loadHomeSnapshot(database, now)),
});
