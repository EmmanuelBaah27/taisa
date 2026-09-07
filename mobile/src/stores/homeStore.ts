import type { HomeView, Insight, LocalNotification, OperationReceipt, WeeklyPeriod, WorkRecord } from '@taisa/shared';
import { create } from 'zustand';

import { selectHome } from '../domain/home/selectHome';
import { withTaisaDatabase } from '../db/openDatabase';
import { loadHomeSnapshot } from '../repositories/homeSnapshotRepository';
import { createHomeOperationService } from '../services/homeOperations';
import type { OperationRequest } from '../domain/operations/operationGate';
import { reconcileNotifications } from '../domain/notifications/notificationPolicy';
import { createHomeUserCommands } from '../services/homeUserCommands';

export interface HomeSnapshot {
  period: WeeklyPeriod;
  records: WorkRecord[];
  insights: Insight[];
  pendingProposalCount: number;
  notifications?: LocalNotification[];
}

export interface CreateTaskInput {
  id: string; title: string; sourceId: string; plannedWeek: string | null; now: string;
}

export interface HomeStoreDependencies {
  load(now: string): Promise<HomeSnapshot>;
  execute?(request: OperationRequest): Promise<OperationReceipt>;
  undo?(receiptId: string, now: string): Promise<OperationReceipt>;
  createTask?(input: CreateTaskInput): Promise<void>;
  reviewWeek?(period: WeeklyPeriod, recordIds: string[], snapshotId: string, now: string): Promise<void>;
  updateNotification?(id: string, change: 'read' | 'dismiss', now: string): Promise<void>;
  snoozeNotification?(id: string, until: string, now: string): Promise<void>;
}

export interface HomeStoreState {
  view: HomeView | null;
  hydratedAt: string | null;
  isHydrating: boolean;
  error: string | null;
  activeReceipt: OperationReceipt | null;
  notifications: LocalNotification[];
  unreadNotificationCount: number;
  hydrate(now: string): Promise<void>;
  completeTask(request: OperationRequest): Promise<void>;
  undoOperation(receiptId: string, now: string): Promise<void>;
  createTask(input: CreateTaskInput): Promise<void>;
  reviewWeek(snapshotId: string, now: string): Promise<void>;
  markNotificationRead(id: string, now: string): Promise<void>;
  dismissNotification(id: string, now: string): Promise<void>;
  snoozeNotification(id: string, until: string, now: string): Promise<void>;
  clearError(): void;
  clearForAuthorityReplacement(): void;
}

export function createHomeStore(dependencies: HomeStoreDependencies) {
  let generation = 0;
  const notificationState = (snapshot: HomeSnapshot, now: string) => {
    const source = snapshot.notifications ?? [];
    const notifications = reconcileNotifications(source, {
      now, mutedGroupingKeys: new Set(),
    }).visible;
    return {
      notifications,
      unreadNotificationCount: source.filter((item) =>
        item.readState === 'unread'
        && item.disposition !== 'dismissed'
        && !(item.disposition === 'snoozed' && item.snoozedUntil !== null && item.snoozedUntil > now),
      ).length,
    };
  };
  return create<HomeStoreState>((set, get) => ({
    view: null,
    hydratedAt: null,
    isHydrating: false,
    error: null,
    activeReceipt: null,
    notifications: [],
    unreadNotificationCount: 0,
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
          ...notificationState(snapshot, now),
        });
      } catch {
        if (current !== generation) return;
        set({
          view: null,
          hydratedAt: null,
          isHydrating: false,
          error: 'The local Home archive is unavailable.',
          notifications: [],
          unreadNotificationCount: 0,
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
          set({ view: selectHome(snapshot), hydratedAt: request.requestedAt,
            ...notificationState(snapshot, request.requestedAt) });
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
        set({ view: selectHome(snapshot), hydratedAt: now, activeReceipt: null,
          ...notificationState(snapshot, now) });
      } catch {
        set({ error: 'The operation could not be undone.' });
      }
    },
    createTask: async (input) => {
      if (dependencies.createTask === undefined) return set({ error: 'Task creation is unavailable.' });
      try {
        await dependencies.createTask(input);
        const snapshot = await dependencies.load(input.now);
        set({ view: selectHome(snapshot), hydratedAt: input.now, error: null, ...notificationState(snapshot, input.now) });
      } catch { set({ error: 'The task could not be created.' }); }
    },
    reviewWeek: async (snapshotId, now) => {
      const view = get().view;
      if (view === null || dependencies.reviewWeek === undefined) return set({ error: 'Weekly review is unavailable.' });
      try {
        const ids = [...view.thisWeek, ...view.carryOver].map((item) => item.id);
        await dependencies.reviewWeek(view.period, ids, snapshotId, now);
        const snapshot = await dependencies.load(now);
        set({ view: selectHome(snapshot), hydratedAt: now, error: null, ...notificationState(snapshot, now) });
      } catch { set({ error: 'The weekly review could not be completed.' }); }
    },
    markNotificationRead: async (id, now) => updateNotificationCommand('read', id, now, dependencies, set, notificationState),
    dismissNotification: async (id, now) => updateNotificationCommand('dismiss', id, now, dependencies, set, notificationState),
    snoozeNotification: async (id, until, now) => {
      if (dependencies.snoozeNotification === undefined) return set({ error: 'Notification snooze is unavailable.' });
      try {
        await dependencies.snoozeNotification(id, until, now);
        const snapshot = await dependencies.load(now);
        set({ view: selectHome(snapshot), hydratedAt: now, error: null, ...notificationState(snapshot, now) });
      } catch { set({ error: 'The notification could not be snoozed.' }); }
    },
    clearError: () => set({ error: null }),
    clearForAuthorityReplacement: () => {
      generation += 1;
      set({ view: null, hydratedAt: null, isHydrating: false, error: null, activeReceipt: null,
        notifications: [], unreadNotificationCount: 0 });
    },
  }));
}

export const useHomeStore = createHomeStore({
  load: (now) => withTaisaDatabase((database) => loadHomeSnapshot(database, now)),
  execute: (request) => withTaisaDatabase((database) => createHomeOperationService(database).execute(request)),
  undo: (receiptId, now) => withTaisaDatabase((database) => createHomeOperationService(database).undo(receiptId, now)),
  createTask: (input) => withTaisaDatabase((database) => createHomeUserCommands(database).createTask(input)),
  reviewWeek: (period, ids, snapshotId, now) => withTaisaDatabase((database) =>
    createHomeUserCommands(database).reviewWeek(period, ids, snapshotId, now)),
  updateNotification: (id, change) => withTaisaDatabase((database) =>
    createHomeUserCommands(database).updateNotification(id, change)),
  snoozeNotification: (id, until, now) => withTaisaDatabase((database) =>
    createHomeUserCommands(database).snoozeNotification(id, until, now)),
});

async function updateNotificationCommand(
  change: 'read' | 'dismiss', id: string, now: string,
  dependencies: HomeStoreDependencies,
  set: (state: Partial<HomeStoreState>) => void,
  notificationState: (snapshot: HomeSnapshot, now: string) => Pick<HomeStoreState, 'notifications' | 'unreadNotificationCount'>,
) {
  if (dependencies.updateNotification === undefined) return set({ error: 'Notification update is unavailable.' });
  try {
    await dependencies.updateNotification(id, change, now);
    const snapshot = await dependencies.load(now);
    set({ view: selectHome(snapshot), hydratedAt: now, error: null, ...notificationState(snapshot, now) });
  } catch { set({ error: 'The notification could not be updated.' }); }
}
