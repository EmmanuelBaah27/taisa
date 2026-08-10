import type { GovernedMemoryDelta, MemoryGovernanceState } from './admission';

const TERMINAL_LIFECYCLES = new Set(['superseded', 'completed', 'rejected', 'archived']);

function hasLiveMemory(state: MemoryGovernanceState, id: string): boolean {
  const item = state.memory.find((candidate) => candidate.id === id);
  return item !== undefined && !TERMINAL_LIFECYCLES.has(item.lifecycle);
}

export function requiresConfirmation(
  delta: GovernedMemoryDelta,
  state: MemoryGovernanceState,
): boolean {
  switch (delta.operation) {
    case 'propose':
      return true;
    case 'transition': {
      return true;
    }
    case 'support':
      return !(
        delta.sourceMessageId.trim().length > 0 &&
        hasLiveMemory(state, delta.targetId)
      );
    case 'link-evidence':
      return !(
        hasLiveMemory(state, delta.targetMemoryId) &&
        state.evidence.some((candidate) => candidate.id === delta.evidenceId)
      );
    case 'complete-action':
      return !(
        delta.explicitlyCompleted &&
        delta.sourceMessageId.trim().length > 0 &&
        state.actions.some(
          (candidate) => candidate.id === delta.targetId && candidate.lifecycle === 'open',
        )
      );
    case 'archive-conversation':
      return !state.conversations.some(
        (candidate) => candidate.id === delta.targetId && candidate.lifecycle === 'active',
      );
    case 'merge':
    case 'delete-memory':
      return true;
  }
}
