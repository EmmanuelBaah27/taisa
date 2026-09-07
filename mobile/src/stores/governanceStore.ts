import type { CapabilitySnapshot, PermittedOperation, ProposalEnvelope } from '@taisa/shared';
import { create } from 'zustand';

import { withTaisaDatabase } from '../db/openDatabase';
import { loadGovernanceSnapshot } from '../repositories/homeSnapshotRepository';
import { createGovernanceActions } from '../services/governanceActions';

export interface GovernanceSnapshot {
  proposals: ProposalEnvelope[];
  capabilities: CapabilitySnapshot[];
}

export interface GovernanceStoreDependencies {
  load(now: string): Promise<GovernanceSnapshot>;
  grant?(operation: PermittedOperation, now: string): Promise<void>;
  revoke?(operation: PermittedOperation, now: string): Promise<void>;
  rejectProposal?(proposalId: string, now: string): Promise<void>;
  acceptProposal?(proposalId: string, now: string): Promise<void>;
}

export interface GovernanceStoreState {
  pendingProposals: ProposalEnvelope[];
  capabilities: CapabilitySnapshot[];
  hydratedAt: string | null;
  isHydrating: boolean;
  error: string | null;
  hydrate(now: string): Promise<void>;
  grantAuthority(operation: PermittedOperation, now: string): Promise<void>;
  askMe(operation: PermittedOperation, now: string): Promise<void>;
  rejectProposal(proposalId: string, now: string): Promise<void>;
  acceptProposal(proposalId: string, now: string): Promise<void>;
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
    grantAuthority: async (operation, now) => {
      if (dependencies.grant === undefined) return set({ error: 'Capability controls are unavailable.' });
      try {
        await dependencies.grant(operation, now);
        const snapshot = await dependencies.load(now);
        set({ capabilities: snapshot.capabilities, pendingProposals: snapshot.proposals, hydratedAt: now, error: null });
      } catch { set({ error: 'Taisa could not grant that capability.' }); }
    },
    askMe: async (operation, now) => {
      if (dependencies.revoke === undefined) return set({ error: 'Capability controls are unavailable.' });
      try {
        await dependencies.revoke(operation, now);
        const snapshot = await dependencies.load(now);
        set({ capabilities: snapshot.capabilities, pendingProposals: snapshot.proposals, hydratedAt: now, error: null });
      } catch { set({ error: 'Taisa could not return that capability to Ask me.' }); }
    },
    rejectProposal: async (proposalId, now) => {
      if (dependencies.rejectProposal === undefined) return set({ error: 'Proposal review is unavailable.' });
      try {
        await dependencies.rejectProposal(proposalId, now);
        const snapshot = await dependencies.load(now);
        set({ capabilities: snapshot.capabilities, pendingProposals: snapshot.proposals, hydratedAt: now, error: null });
      } catch { set({ error: 'The proposal could not be reviewed.' }); }
    },
    acceptProposal: async (proposalId, now) => {
      if (dependencies.acceptProposal === undefined) return set({ error: 'Proposal acceptance is unavailable.' });
      try {
        await dependencies.acceptProposal(proposalId, now);
        const snapshot = await dependencies.load(now);
        set({ capabilities: snapshot.capabilities, pendingProposals: snapshot.proposals, hydratedAt: now, error: null });
      } catch { set({ error: 'The proposal could not be applied.' }); }
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
  grant: (operation, now) => withTaisaDatabase((database) => createGovernanceActions(database).grant(operation, now)),
  revoke: (operation, now) => withTaisaDatabase((database) => createGovernanceActions(database).revoke(operation, now)),
  rejectProposal: (id, now) => withTaisaDatabase((database) => createGovernanceActions(database).rejectProposal(id, now)),
  acceptProposal: (id, now) => withTaisaDatabase((database) => createGovernanceActions(database).acceptProposal(id, now)),
});
