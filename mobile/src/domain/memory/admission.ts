import type {
  LocalAction,
  LocalConversation,
  LocalEvidenceItem,
  LocalMessage,
  MemoryDelta,
  MemoryItem,
} from '@taisa/shared';

import { requiresConfirmation } from './confirmationPolicy';

export type MemoryChangeKind = 'create' | 'replace' | 'merge' | 'promote-fact';
export type MemorySensitivity = 'none' | 'sensitive' | 'identity' | 'unclassified';

export type GovernedProposeDelta = Extract<MemoryDelta, { operation: 'propose' }> & {
  changeKind: MemoryChangeKind;
  sensitivity: MemorySensitivity;
  materialToFutureCoaching: boolean;
  conflictsWithIds: readonly string[];
};

export type GovernedMemoryDelta =
  | GovernedProposeDelta
  | Extract<MemoryDelta, { operation: 'transition' | 'support' }>
  | {
      operation: 'link-evidence';
      targetMemoryId: string;
      evidenceId: string;
      reason: string;
      requiresConfirmation: boolean;
    }
  | {
      operation: 'complete-action';
      targetId: string;
      explicitlyCompleted: boolean;
      sourceMessageId: string;
      reason: string;
      requiresConfirmation: boolean;
    }
  | {
      operation: 'archive-conversation';
      targetId: string;
      reason: string;
      requiresConfirmation: boolean;
    }
  | {
      operation: 'merge';
      sourceIds: readonly string[];
      reason: string;
      requiresConfirmation: boolean;
    }
  | {
      operation: 'delete-memory';
      targetId: string;
      reason: string;
      requiresConfirmation: boolean;
    };

export interface MemoryGovernanceState {
  memory: readonly MemoryItem[];
  actions: readonly Pick<LocalAction, 'id' | 'lifecycle'>[];
  conversations: readonly Pick<LocalConversation, 'id' | 'lifecycle'>[];
  evidence: readonly Pick<LocalEvidenceItem, 'id'>[];
}

export type MemoryAdmissionResult =
  | { status: 'archive-only'; reason: 'not-material-to-future-coaching' }
  | { status: 'automatic'; delta: GovernedMemoryDelta }
  | { status: 'confirmation-required'; delta: GovernedMemoryDelta }
  | {
      status: 'clarification-required';
      question: string;
      candidate: GovernedProposeDelta;
      preservedMemoryIds: string[];
      proposedTransitions: Array<Extract<MemoryDelta, { operation: 'transition' }>>;
    };

export type GatewayMemoryAdmissionResult =
  | MemoryAdmissionResult
  | { status: 'rejected'; reason: 'unknown-target' | 'non-live-target' | 'untrusted-source' };

export interface TrustedMemoryAdmissionContext {
  conversationId: string;
  sourceMessage: Pick<
    LocalMessage,
    'id' | 'conversationId' | 'role' | 'lifecycle'
  >;
}

function compareStable(left: string, right: string): number {
  if (left < right) return -1;
  if (left > right) return 1;
  return 0;
}

function activeConflictIds(
  delta: GovernedProposeDelta,
  state: MemoryGovernanceState,
): string[] {
  const declared = new Set(delta.conflictsWithIds);
  return state.memory
    .filter(
      (item) =>
        declared.has(item.id) &&
        (item.lifecycle === 'active' || item.lifecycle === 'paused'),
    )
    .map((item) => item.id)
    .sort(compareStable);
}

export function assessMemoryAdmission(
  delta: GovernedMemoryDelta,
  state: MemoryGovernanceState,
): MemoryAdmissionResult {
  if (delta.operation === 'propose' && !delta.materialToFutureCoaching) {
    return {
      status: 'archive-only',
      reason: 'not-material-to-future-coaching',
    };
  }

  if (delta.operation === 'propose') {
    const conflicts = activeConflictIds(delta, state);
    if (conflicts.length > 0) {
      const firstConflict = state.memory.find((item) => item.id === conflicts[0])!;
      return {
        status: 'clarification-required',
        question: `You previously set “${firstConflict.statement}.” Does “${delta.candidate.statement}” replace that direction, pause it, or sit alongside it?`,
        candidate: delta,
        preservedMemoryIds: conflicts,
        proposedTransitions: conflicts.map((targetId) => ({
          operation: 'transition',
          targetId,
          to: 'superseded',
          reason:
            'User confirmation is required before replacing a conflicting career direction.',
          requiresConfirmation: true,
        })),
      };
    }
  }

  if (requiresConfirmation(delta, state)) {
    return { status: 'confirmation-required', delta };
  }

  return { status: 'automatic', delta };
}

function liveTarget(state: MemoryGovernanceState, id: string): MemoryItem | null {
  const target = state.memory.find((item) => item.id === id);
  if (target === undefined) return null;
  return target.lifecycle === 'active' ||
    target.lifecycle === 'paused' ||
    target.lifecycle === 'proposed'
    ? target
    : null;
}

export function admitGatewayMemoryDelta(
  delta: MemoryDelta,
  state: MemoryGovernanceState,
  context: TrustedMemoryAdmissionContext,
): GatewayMemoryAdmissionResult {
  const { sourceMessage } = context;
  if (
    sourceMessage.conversationId !== context.conversationId ||
    sourceMessage.role !== 'user' ||
    sourceMessage.lifecycle !== 'submitted'
  ) {
    return { status: 'rejected', reason: 'untrusted-source' };
  }

  switch (delta.operation) {
    case 'propose': {
      const supersedesId = delta.candidate.supersedesId ?? null;
      if (supersedesId !== null) {
        const target = state.memory.find((item) => item.id === supersedesId);
        if (target === undefined) return { status: 'rejected', reason: 'unknown-target' };
        if (liveTarget(state, supersedesId) === null) {
          return { status: 'rejected', reason: 'non-live-target' };
        }
      }
      const governed: GovernedProposeDelta = {
        operation: 'propose',
        candidate: {
          ...delta.candidate,
          provenance: 'ai-inferred',
          lifecycle: 'proposed',
          confidence: 'tentative',
          sourceMessageIds: [sourceMessage.id],
          supersedesId,
        },
        reason: delta.reason,
        requiresConfirmation: true,
        changeKind: supersedesId === null ? 'create' : 'replace',
        sensitivity: 'unclassified',
        materialToFutureCoaching: true,
        conflictsWithIds: supersedesId === null ? [] : [supersedesId],
      };
      return assessMemoryAdmission(governed, state);
    }
    case 'transition': {
      const target = state.memory.find((item) => item.id === delta.targetId);
      if (target === undefined) return { status: 'rejected', reason: 'unknown-target' };
      if (liveTarget(state, delta.targetId) === null) {
        return { status: 'rejected', reason: 'non-live-target' };
      }
      return assessMemoryAdmission(
        { ...delta, requiresConfirmation: true },
        state,
      );
    }
    case 'support': {
      const target = state.memory.find((item) => item.id === delta.targetId);
      if (target === undefined) return { status: 'rejected', reason: 'unknown-target' };
      if (liveTarget(state, delta.targetId) === null) {
        return { status: 'rejected', reason: 'non-live-target' };
      }
      return assessMemoryAdmission(
        {
          ...delta,
          sourceMessageId: sourceMessage.id,
          requiresConfirmation: false,
        },
        state,
      );
    }
  }
}
