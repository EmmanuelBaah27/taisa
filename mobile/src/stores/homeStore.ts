import type { HomeView, Insight, OperationReceipt, WeeklyPeriod, WorkRecord } from '@taisa/shared';
import { create } from 'zustand';

import { selectHome } from '../domain/home/selectHome';
import { withTaisaDatabase } from '../db/openDatabase';
import { loadHomeSnapshot } from '../repositories/homeSnapshotRepository';
import { createHomeOperationService } from '../services/homeOperations';
import type { OperationRequest } from '../domain/operations/operationGate';

export interface HomeSnapshot {
  period: WeeklyPeriod;
  records: WorkRecord[];
  insights: Insight[];
  pendingProposalCount: number;
}

export interface HomeStoreDependencies {
  load(now: string): Promise<HomeSnapshot>;
  execute?(request: OperationRequest): Promise<OperationReceipt>;
  undo?(receiptId: string, now: string): Promise<OperationReceipt>;
}

export interface HomeStoreState {
  view: HomeView | null;
  hydratedAt: string | null;
  isHydrating: boolean;
  error: string | null;
  activeReceipt: OperationReceipt | null;
  hydrate(now: string): Promise<void>;
  completeTask(request: OperationRequest): Promise<void>;
  undoOperation(receiptId: string, now: string): Promise<void>;
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
    activeReceipt: null,
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
    completeTask: async (request) => {
      if (request.operation !== 'complete_explicit_task' || dependencies.execute === undefined) {
        set({ error: 'This task operation is unavailable.' });
        return;
      }
      set({ error: null });
      try {
        const activeReceipt = await dependencies.execute(request);
        set({ activeReceipt });
        await dependencies.load(request.requestedAt).then((snapshot) => {
          set({ view: selectHome(snapshot), hydratedAt: request.requestedAt });
        });
      } catch {
        set({ error: 'The task could not be completed.' });
      }
    },
    undoOperation: async (receiptId, now) => {
      if (dependencies.undo === undefined) {
        set({ error: 'Undo is unavailable.' });
        return;
      }
      set({ error: null });
      try {
        await dependencies.undo(receiptId, now);
        const snapshot = await dependencies.load(now);
        set({ view: selectHome(snapshot), hydratedAt: now, activeReceipt: null });
      } catch {
        set({ error: 'The operation could not be undone.' });
      }
    },
    clearError: () => set({ error: null }),
    clearForAuthorityReplacement: () => {
      generation += 1;
      set({ view: null, hydratedAt: null, isHydrating: false, error: null, activeReceipt: null });
    },
  }));
}

export const useHomeStore = createHomeStore({
  load: (now) => withTaisaDatabase((database) => loadHomeSnapshot(database, now)),
  execute: (request) => withTaisaDatabase((database) => createHomeOperationService(database).execute(request)),
  undo: (receiptId, now) => withTaisaDatabase((database) => createHomeOperationService(database).undo(receiptId, now)),
});
