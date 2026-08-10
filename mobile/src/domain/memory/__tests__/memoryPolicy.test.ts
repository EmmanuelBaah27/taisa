import type {
  LocalAction,
  LocalConversation,
  LocalEvidenceItem,
  MemoryDelta,
  MemoryItem,
} from '@taisa/shared';

import {
  admitGatewayMemoryDelta,
  assessMemoryAdmission,
  type GovernedMemoryDelta,
  type MemoryGovernanceState,
} from '../admission';
import { requiresConfirmation } from '../confirmationPolicy';

const NOW = '2026-08-10T09:00:00.000Z';

const staffGoal: MemoryItem = {
  id: 'memory-staff-goal',
  type: 'goal',
  statement: 'Become a Staff Product Designer',
  provenance: 'user-confirmed',
  lifecycle: 'active',
  confidence: 'established',
  createdAt: NOW,
  confirmedAt: NOW,
  lastSupportedAt: NOW,
  statusChangedAt: NOW,
  sourceMessageIds: ['message-staff-goal'],
  supersedesId: null,
};

const icDecision: MemoryItem = {
  ...staffGoal,
  id: 'memory-ic-decision',
  type: 'decision',
  statement: 'Stay on the individual-contributor path',
};

const preference: MemoryItem = {
  ...staffGoal,
  id: 'memory-preference',
  type: 'preference',
  statement: 'Prefer ownership over people management',
};

const action: LocalAction = {
  id: 'action-roadmap',
  goalId: null,
  sourceMessageId: 'message-action',
  title: 'Lead the roadmap workshop',
  description: null,
  lifecycle: 'open',
  priority: 'high',
  dueAt: null,
  supersedesId: null,
  createdAt: NOW,
  updatedAt: NOW,
  statusChangedAt: NOW,
};

const conversation: LocalConversation = {
  id: 'conversation-roadmap',
  title: 'Roadmap reflection',
  lifecycle: 'active',
  createdAt: NOW,
  updatedAt: NOW,
  archivedAt: null,
};

const evidence: LocalEvidenceItem = {
  id: 'evidence-workshop',
  statement: 'Led a roadmap workshop',
  occurredAt: NOW,
  sourceMessageIds: ['message-evidence'],
  goalIds: [],
  actionIds: [action.id],
  createdAt: NOW,
  updatedAt: NOW,
};

const state: MemoryGovernanceState = {
  memory: [staffGoal, icDecision, preference],
  actions: [action],
  conversations: [conversation],
  evidence: [evidence],
};

function proposal(
  overrides: Partial<Extract<GovernedMemoryDelta, { operation: 'propose' }>> = {},
): Extract<GovernedMemoryDelta, { operation: 'propose' }> {
  return {
    operation: 'propose',
    candidate: {
      type: 'career_context',
      statement: 'My role now includes product strategy',
      provenance: 'user-stated',
      lifecycle: 'active',
      confidence: 'established',
      sourceMessageIds: ['message-current'],
      supersedesId: null,
    },
    reason: 'The user stated a durable role change.',
    requiresConfirmation: false,
    changeKind: 'create',
    sensitivity: 'none',
    materialToFutureCoaching: true,
    conflictsWithIds: [],
    ...overrides,
  };
}

describe('governed memory confirmation policy', () => {
  test.each([
    ['new durable context proposed by AI output', proposal()],
    ['new goal', proposal({ candidate: { ...proposal().candidate, type: 'goal' } })],
    [
      'replacement goal',
      proposal({
        candidate: {
          ...proposal().candidate,
          type: 'goal',
          supersedesId: staffGoal.id,
        },
        changeKind: 'replace',
      }),
    ],
    ['sensitive interpretation', proposal({ sensitivity: 'sensitive' })],
    ['identity-level interpretation', proposal({ sensitivity: 'identity' })],
    ['fact promotion', proposal({ changeKind: 'promote-fact' })],
    [
      'preference supersession',
      {
        operation: 'transition',
        targetId: preference.id,
        to: 'superseded',
        reason: 'A new preference may replace it.',
        requiresConfirmation: false,
      } satisfies GovernedMemoryDelta,
    ],
    [
      'decision supersession',
      {
        operation: 'transition',
        targetId: icDecision.id,
        to: 'superseded',
        reason: 'A new decision may replace it.',
        requiresConfirmation: false,
      } satisfies GovernedMemoryDelta,
    ],
    [
      'merge',
      {
        operation: 'merge',
        sourceIds: [staffGoal.id, icDecision.id],
        reason: 'These records may express one direction.',
        requiresConfirmation: false,
      } satisfies GovernedMemoryDelta,
    ],
    [
      'history deletion',
      {
        operation: 'delete-memory',
        targetId: staffGoal.id,
        reason: 'Remove the old direction.',
        requiresConfirmation: false,
      } satisfies GovernedMemoryDelta,
    ],
  ] as const)('requires confirmation for %s even when the AI says it does not', (_label, delta) => {
    expect(requiresConfirmation(delta, state)).toBe(true);
  });

  test.each([
    [
      'support for an existing record',
      {
        operation: 'support',
        targetId: staffGoal.id,
        sourceMessageId: 'message-current',
        reason: 'The current moment supports the goal.',
        requiresConfirmation: false,
      } satisfies GovernedMemoryDelta,
    ],
    [
      'evidence link to an existing record',
      {
        operation: 'link-evidence',
        targetMemoryId: staffGoal.id,
        evidenceId: evidence.id,
        reason: 'The evidence directly supports this goal.',
        requiresConfirmation: false,
      } satisfies GovernedMemoryDelta,
    ],
    [
      'explicit completion of an open action',
      {
        operation: 'complete-action',
        targetId: action.id,
        explicitlyCompleted: true,
        sourceMessageId: 'message-current',
        reason: 'The user explicitly said the action is complete.',
        requiresConfirmation: false,
      } satisfies GovernedMemoryDelta,
    ],
    [
      'archival of an active conversation',
      {
        operation: 'archive-conversation',
        targetId: conversation.id,
        reason: 'The conversation is finished.',
        requiresConfirmation: false,
      } satisfies GovernedMemoryDelta,
    ],
  ] as const)('allows narrowly proven safe automatic operation: %s', (_label, delta) => {
    expect(requiresConfirmation(delta, state)).toBe(false);
    expect(assessMemoryAdmission(delta, state)).toMatchObject({ status: 'automatic' });
  });

  test('fails closed when an allegedly safe operation cannot be proven from local state', () => {
    expect(
      requiresConfirmation(
        {
          operation: 'complete-action',
          targetId: 'missing-action',
          explicitlyCompleted: true,
          sourceMessageId: 'message-current',
          reason: 'Unverifiable completion.',
          requiresConfirmation: false,
        },
        state,
      ),
    ).toBe(true);
  });
});

describe('memory admission and temporal conflicts', () => {
  test('enriches an actual gateway proposal locally and treats supersedesId as a conflict', () => {
    const gatewayDelta: MemoryDelta = {
      operation: 'propose',
      candidate: {
        type: 'goal',
        statement: 'Move into product design management',
        provenance: 'ai-inferred',
        lifecycle: 'active',
        confidence: 'tentative',
        sourceMessageIds: ['provider-invented-source'],
        supersedesId: staffGoal.id,
      },
      reason: 'This may be a new direction.',
      requiresConfirmation: false,
    };

    expect(
      admitGatewayMemoryDelta(gatewayDelta, state, {
        conversationId: conversation.id,
        sourceMessage: {
          id: 'message-current',
          conversationId: conversation.id,
          role: 'user',
          lifecycle: 'submitted',
        },
      }),
    ).toMatchObject({
      status: 'clarification-required',
      candidate: {
        changeKind: 'replace',
        sensitivity: 'unclassified',
        conflictsWithIds: [staffGoal.id],
        candidate: {
          sourceMessageIds: ['message-current'],
          supersedesId: staffGoal.id,
        },
      },
      preservedMemoryIds: [staffGoal.id],
    });
  });

  test.each([
    {
      operation: 'propose' as const,
      candidate: {
        ...proposal().candidate,
        supersedesId: 'memory-missing',
      },
      reason: 'Replace a missing record.',
      requiresConfirmation: false,
    },
    {
      operation: 'transition' as const,
      targetId: 'memory-missing',
      to: 'superseded' as const,
      reason: 'Transition a missing record.',
      requiresConfirmation: false,
    },
    {
      operation: 'support' as const,
      targetId: 'memory-missing',
      sourceMessageId: 'provider-invented-source',
      reason: 'Support a missing record.',
      requiresConfirmation: false as const,
    },
  ])('rejects gateway deltas with unknown targets', (gatewayDelta) => {
    expect(
      admitGatewayMemoryDelta(gatewayDelta, state, {
        conversationId: conversation.id,
        sourceMessage: {
          id: 'message-current',
          conversationId: conversation.id,
          role: 'user',
          lifecycle: 'submitted',
        },
      }),
    ).toEqual({ status: 'rejected', reason: 'unknown-target' });
  });

  test('rejects gateway admission without a current submitted local user message', () => {
    expect(
      admitGatewayMemoryDelta(
        {
          operation: 'support',
          targetId: staffGoal.id,
          sourceMessageId: 'provider-invented-source',
          reason: 'Support the goal.',
          requiresConfirmation: false,
        },
        state,
        {
          conversationId: conversation.id,
          sourceMessage: {
            id: 'message-private',
            conversationId: conversation.id,
            role: 'assistant',
            lifecycle: 'private',
          },
        },
      ),
    ).toEqual({ status: 'rejected', reason: 'untrusted-source' });
  });

  test('keeps ordinary detail in the conversation archive instead of durable memory', () => {
    expect(
      assessMemoryAdmission(proposal({ materialToFutureCoaching: false }), state),
    ).toEqual({
      status: 'archive-only',
      reason: 'not-material-to-future-coaching',
    });
  });

  test('stages clarification and an explicit transition for management versus Staff', () => {
    const managementGoal = proposal({
      candidate: {
        ...proposal().candidate,
        type: 'goal',
        statement: 'Move into product design management',
        supersedesId: staffGoal.id,
      },
      changeKind: 'replace',
      conflictsWithIds: [staffGoal.id],
    });
    const originalState = JSON.stringify(state);

    const result = assessMemoryAdmission(managementGoal, state);

    expect(result).toEqual({
      status: 'clarification-required',
      question:
        'You previously set “Become a Staff Product Designer.” Does “Move into product design management” replace that direction, pause it, or sit alongside it?',
      candidate: managementGoal,
      preservedMemoryIds: [staffGoal.id],
      proposedTransitions: [
        {
          operation: 'transition',
          targetId: staffGoal.id,
          to: 'superseded',
          reason: 'User confirmation is required before replacing a conflicting career direction.',
          requiresConfirmation: true,
        },
      ],
    });
    expect(JSON.stringify(state)).toBe(originalState);
  });

  test('does not invent a conflict from text similarity without explicit related IDs', () => {
    expect(
      assessMemoryAdmission(
        proposal({
          candidate: {
            ...proposal().candidate,
            type: 'goal',
            statement: 'Become a Staff-level design manager',
          },
        }),
        state,
      ),
    ).toMatchObject({ status: 'confirmation-required' });
  });
});
