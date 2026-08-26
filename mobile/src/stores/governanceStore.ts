import type { CapabilitySnapshot, ProposalEnvelope } from '@taisa/shared';
import { create } from 'zustand';

import { withTaisaDatabase } from '../db/openDatabase';
import { loadGovernanceSnapshot } from '../repositories/homeSnapshotRepository';

export interface GovernanceSnapshot {
  proposals: ProposalEnvelope[];
  capabilities: CapabilitySnapshot[];
}

export interface GovernanceStoreDependencies {
  load(now: string): Promise<GovernanceSnapshot>;
}

export interface GovernanceStoreState {
  pendingProposals: ProposalEnvelope[];
  capabilities: CapabilitySnapshot[];
  hydratedAt: string | null;
  isHydrating: boolean;
  error: string | null;
  hydrate(now: string): Promise<void>;
  clearError(): void;
  clearForAuthorityReplacement(): void;
}

export function createGovernanceStore(dependencies: GovernanceStoreDependencies) {
  let generation = 0;
  return create<GovernanceStoreState>((set) => ({
    pendingProposals: [],
    capabilities: [],
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
          pendingProposals: snapshot.proposals,
          capabilities: snapshot.capabilities,
          hydratedAt: now,
          isHydrating: false,
        });
      } catch {
        if (current !== generation) return;
        set({
          pendingProposals: [], capabilities: [], hydratedAt: null,
          isHydrating: false, error: 'Taisa’s local governance state is unavailable.',
        });
      }
    },
    clearError: () => set({ error: null }),
    clearForAuthorityReplacement: () => {
      generation += 1;
      set({
        pendingProposals: [], capabilities: [], hydratedAt: null,
        isHydrating: false, error: null,
      });
    },
  }));
}

export const useGovernanceStore = createGovernanceStore({
  load: () => withTaisaDatabase(loadGovernanceSnapshot),
});
