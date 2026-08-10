import type {
  LocalAction,
  LocalConversation,
  LocalMemoryItem,
  LocalMemorySource,
} from '@taisa/shared';

import type { RepositoryTransaction } from '../../db/types';

import { getAction, updateAction } from '../../repositories/actionRepository';
import { insertActionTransition } from '../../repositories/actionTransitionRepository';
import {
  getConversation,
  getMessage,
  updateConversation,
} from '../../repositories/conversationRepository';
import { getEvidence } from '../../repositories/evidenceRepository';
import {
  getMemory,
  insertMemory,
  linkMemorySource,
  updateMemory,
} from '../../repositories/memoryRepository';
import { claimMutation } from '../../repositories/mutationReceipt';
import type { GovernedMemoryDelta, MemoryGovernanceState } from './admission';
import { consumeConfirmedMemoryResolution } from './confirmationWorkflow';
import { requiresConfirmation } from './confirmationPolicy';

export type DeltaAuthorization =
  | { kind: 'confirmed-record'; confirmationId: string }
  | { kind: 'safe-automatic' };

export interface ConfirmedDeltaApplication {
  delta: GovernedMemoryDelta;
  authorization: DeltaAuthorization;
  idempotencyId: string;
  effectiveAt: string;
  newMemoryId?: string;
  transitionId?: string;
  trustedContext?: {
    conversationId: string;
    sourceMessageId: string;
    requestId: string;
  };
  sourceLinks: readonly LocalMemorySource[];
}

export interface ConfirmedConflictResolutionApplication {
  confirmationId: string;
  idempotencyId: string;
  effectiveAt: string;
  successorId: string;
  candidate: Extract<GovernedMemoryDelta, { operation: 'propose' }>;
  predecessorIds: readonly string[];
  sourceLinks: readonly LocalMemorySource[];
}

export type ClarificationResolutionChoice = 'replace' | 'pause' | 'coexist';

export interface ConfirmedClarificationResolutionApplication {
  confirmationId: string;
  idempotencyId: string;
  effectiveAt: string;
  successorId: string;
  candidate: Extract<GovernedMemoryDelta, { operation: 'propose' }>;
  predecessorIds: readonly string[];
  choice: ClarificationResolutionChoice;
  sourceLinks: readonly LocalMemorySource[];
}

export class UnsafeAutomaticDeltaError extends Error {
  readonly code = 'UNSAFE_AUTOMATIC_DELTA';

  constructor() {
    super('This change requires explicit user confirmation');
    this.name = 'UnsafeAutomaticDeltaError';
  }
}

export class InvalidDeltaApplicationError extends Error {
  readonly code = 'INVALID_DELTA_APPLICATION';

  constructor(message: string) {
    super(message);
    this.name = 'InvalidDeltaApplicationError';
  }
}

function requireNonEmpty(value: string | undefined, label: string): string {
  if (value === undefined || value.trim().length === 0) {
    throw new InvalidDeltaApplicationError(`${label} must not be empty`);
  }
  return value;
}

function memoryIdsFor(delta: GovernedMemoryDelta): string[] {
  switch (delta.operation) {
    case 'propose':
      return [...delta.conflictsWithIds];
    case 'transition':
    case 'support':
    case 'delete-memory':
      return [delta.targetId];
    case 'link-evidence':
      return [delta.targetMemoryId];
    case 'merge':
      return [...delta.sourceIds];
    case 'complete-action':
    case 'archive-conversation':
      return [];
  }
}

async function loadGovernanceState(
  transaction: RepositoryTransaction,
  delta: GovernedMemoryDelta,
): Promise<MemoryGovernanceState> {
  const memory = (
    await Promise.all(memoryIdsFor(delta).map((id) => getMemory(transaction, id)))
  ).flatMap((item) => (item === null ? [] : [item]));
  const actions: Pick<LocalAction, 'id' | 'lifecycle'>[] = [];
  const conversations: Pick<LocalConversation, 'id' | 'lifecycle'>[] = [];
  const evidence: Array<{ id: string }> = [];

  if (delta.operation === 'complete-action') {
    const action = await getAction(transaction, delta.targetId);
    if (action !== null) actions.push(action);
  }
  if (delta.operation === 'archive-conversation') {
    const conversation = await getConversation(transaction, delta.targetId);
    if (conversation !== null) conversations.push(conversation);
  }
  if (delta.operation === 'link-evidence') {
    const item = await getEvidence(transaction, delta.evidenceId);
    if (item !== null) evidence.push(item);
  }

  return { memory, actions, conversations, evidence };
}

function validateSourceLinks(
  memoryItemId: string,
  sourceLinks: readonly LocalMemorySource[],
  requiredMessageIds: readonly string[] = [],
  requiredEvidenceIds: readonly string[] = [],
): void {
  if (sourceLinks.length === 0) {
    throw new InvalidDeltaApplicationError('A memory change must retain at least one source');
  }

  const sourceIds = new Set<string>();
  const messageIds = new Set<string>();
  const evidenceIds = new Set<string>();
  for (const source of sourceLinks) {
    if (source.memoryItemId !== memoryItemId) {
      throw new InvalidDeltaApplicationError('Memory source targets the wrong memory item');
    }
    const sourceCount = Number(source.messageId !== null) + Number(source.evidenceId !== null);
    if (sourceCount !== 1) {
      throw new InvalidDeltaApplicationError('Memory source must reference exactly one local source');
    }
    if (sourceIds.has(source.id)) {
      throw new InvalidDeltaApplicationError('Memory source IDs must be unique');
    }
    sourceIds.add(source.id);
    if (source.messageId !== null) messageIds.add(source.messageId);
    if (source.evidenceId !== null) evidenceIds.add(source.evidenceId);
  }

  if (requiredMessageIds.some((id) => !messageIds.has(id))) {
    throw new InvalidDeltaApplicationError('A declared message source is missing its trace link');
  }
  if (requiredEvidenceIds.some((id) => !evidenceIds.has(id))) {
    throw new InvalidDeltaApplicationError('A declared evidence source is missing its trace link');
  }
}

function incrementConfidence(confidence: LocalMemoryItem['confidence']): LocalMemoryItem['confidence'] {
  if (confidence === 'tentative') return 'supported';
  return 'established';
}

function stableCompare(left: string, right: string): number {
  if (left < right) return -1;
  if (left > right) return 1;
  return 0;
}

function sortedUnique(values: readonly string[]): string[] {
  return [...new Set(values)].sort(stableCompare);
}

function normalizedSourceLinks(sourceLinks: readonly LocalMemorySource[]): LocalMemorySource[] {
  return [...sourceLinks]
    .map((source) => ({ ...source }))
    .sort((left, right) => stableCompare(left.id, right.id));
}

export function confirmedDeltaResolutionPayload(application: ConfirmedDeltaApplication): unknown {
  return {
    kind: 'apply-delta',
    proposal: application.delta,
    delta: application.delta,
    effectiveAt: application.effectiveAt,
    newMemoryId: application.newMemoryId ?? null,
    transitionId: application.transitionId ?? null,
    trustedContext: application.trustedContext ?? null,
    sourceLinks: normalizedSourceLinks(application.sourceLinks),
  };
}

export function confirmedConflictResolutionPayload(
  application: ConfirmedConflictResolutionApplication,
): unknown {
  return {
    kind: 'resolve-conflict',
    proposal: application.candidate,
    effectiveAt: application.effectiveAt,
    successorId: application.successorId,
    candidate: {
      ...application.candidate,
      candidate: {
        ...application.candidate.candidate,
        sourceMessageIds: sortedUnique(application.candidate.candidate.sourceMessageIds),
      },
      conflictsWithIds: sortedUnique(application.candidate.conflictsWithIds),
    },
    predecessorIds: sortedUnique(application.predecessorIds),
    sourceLinks: normalizedSourceLinks(application.sourceLinks),
  };
}

export function confirmedClarificationResolutionPayload(
  application: ConfirmedClarificationResolutionApplication,
): unknown {
  return {
    kind: 'resolve-clarification',
    proposal: application.candidate,
    choice: application.choice,
    effectiveAt: application.effectiveAt,
    successorId: application.successorId,
    candidate: {
      ...application.candidate,
      candidate: {
        ...application.candidate.candidate,
        sourceMessageIds: sortedUnique(application.candidate.candidate.sourceMessageIds),
      },
      conflictsWithIds: sortedUnique(application.candidate.conflictsWithIds),
    },
    predecessorIds: sortedUnique(application.predecessorIds),
    sourceLinks: normalizedSourceLinks(application.sourceLinks),
  };
}

function applicationTargetId(application: ConfirmedDeltaApplication): string {
  const { delta } = application;
  switch (delta.operation) {
    case 'propose':
      return requireNonEmpty(application.newMemoryId, 'New memory ID');
    case 'link-evidence':
      return delta.targetMemoryId;
    case 'merge':
      return [...delta.sourceIds].sort().join(',');
    default:
      return delta.targetId;
  }
}

async function applySourceLinks(
  transaction: RepositoryTransaction,
  sourceLinks: readonly LocalMemorySource[],
  idempotencyId: string,
): Promise<void> {
  for (const source of sourceLinks) {
    await linkMemorySource(
      transaction,
      source,
      `${idempotencyId}:source:${source.id}`,
    );
  }
}

async function validateActionCompletionSource(
  transaction: RepositoryTransaction,
  application: ConfirmedDeltaApplication,
  delta: Extract<GovernedMemoryDelta, { operation: 'complete-action' }>,
): Promise<{
  transitionId: string;
  conversationId: string;
  sourceMessageId: string;
  requestId: string;
}> {
  const context = application.trustedContext;
  const transitionId = requireNonEmpty(application.transitionId, 'Action transition ID');
  if (context === undefined || delta.sourceMessageId !== context.sourceMessageId) {
    throw new UnsafeAutomaticDeltaError();
  }
  const message = await getMessage(transaction, context.sourceMessageId);
  if (
    message === null ||
    message.role !== 'user' ||
    message.lifecycle !== 'submitted' ||
    message.conversationId !== context.conversationId ||
    message.requestId === null ||
    message.requestId !== context.requestId
  ) {
    throw new UnsafeAutomaticDeltaError();
  }
  return {
    transitionId,
    conversationId: context.conversationId,
    sourceMessageId: context.sourceMessageId,
    requestId: context.requestId,
  };
}

export async function applyConfirmedDelta(
  transaction: RepositoryTransaction,
  application: ConfirmedDeltaApplication,
): Promise<void> {
  requireNonEmpty(application.idempotencyId, 'Idempotency ID');
  requireNonEmpty(application.effectiveAt, 'Effective timestamp');
  if (application.authorization.kind === 'confirmed-record') {
    requireNonEmpty(application.authorization.confirmationId, 'Confirmation ID');
  }

  const targetId = applicationTargetId(application);
  if (!(await claimMutation(
    transaction,
    application.idempotencyId,
    'governed-delta',
    targetId,
    application.delta.operation,
    application,
  ))) {
    return;
  }
  if (application.authorization.kind === 'safe-automatic') {
    const state = await loadGovernanceState(transaction, application.delta);
    if (requiresConfirmation(application.delta, state)) {
      throw new UnsafeAutomaticDeltaError();
    }
  } else {
    await consumeConfirmedMemoryResolution(transaction, {
      confirmationId: application.authorization.confirmationId,
      resolution: confirmedDeltaResolutionPayload(application),
      consumedAt: application.effectiveAt,
      consumedByIdempotencyId: application.idempotencyId,
    });
  }

  const { delta, effectiveAt, idempotencyId, sourceLinks } = application;
  switch (delta.operation) {
    case 'propose': {
      if (
        delta.candidate.supersedesId != null ||
        delta.conflictsWithIds.length > 0 ||
        delta.changeKind === 'replace' ||
        delta.changeKind === 'merge'
      ) {
        throw new InvalidDeltaApplicationError(
          'Replacement memory must use the bundled conflict-resolution operation',
        );
      }
      const memoryId = requireNonEmpty(application.newMemoryId, 'New memory ID');
      validateSourceLinks(memoryId, sourceLinks, delta.candidate.sourceMessageIds);
      const memory: LocalMemoryItem = {
        ...delta.candidate,
        id: memoryId,
        lifecycle: 'active',
        createdAt: effectiveAt,
        confirmedAt: effectiveAt,
        lastSupportedAt: effectiveAt,
        statusChangedAt: effectiveAt,
        updatedAt: effectiveAt,
        sourceMessageIds: [...delta.candidate.sourceMessageIds],
        sourceEvidenceIds: sourceLinks.flatMap((source) =>
          source.evidenceId === null ? [] : [source.evidenceId],
        ),
      };
      await insertMemory(transaction, memory, `${idempotencyId}:memory`);
      await applySourceLinks(transaction, sourceLinks, idempotencyId);
      return;
    }
    case 'transition': {
      if (delta.to === 'superseded') {
        throw new InvalidDeltaApplicationError(
          'Supersession must use the bundled conflict-resolution operation',
        );
      }
      const current = await getMemory(transaction, delta.targetId);
      if (current === null) {
        throw new InvalidDeltaApplicationError('Cannot transition missing memory');
      }
      validateSourceLinks(current.id, sourceLinks);
      await updateMemory(
        transaction,
        {
          ...current,
          lifecycle: delta.to,
          updatedAt: effectiveAt,
          statusChangedAt: effectiveAt,
        },
        `${idempotencyId}:memory`,
      );
      await applySourceLinks(transaction, sourceLinks, idempotencyId);
      return;
    }
    case 'support': {
      const current = await getMemory(transaction, delta.targetId);
      if (current === null) {
        throw new InvalidDeltaApplicationError('Cannot support missing memory');
      }
      validateSourceLinks(current.id, sourceLinks, [delta.sourceMessageId]);
      await updateMemory(
        transaction,
        {
          ...current,
          confidence: incrementConfidence(current.confidence),
          lastSupportedAt: effectiveAt,
          updatedAt: effectiveAt,
        },
        `${idempotencyId}:memory`,
      );
      await applySourceLinks(transaction, sourceLinks, idempotencyId);
      return;
    }
    case 'link-evidence': {
      const current = await getMemory(transaction, delta.targetMemoryId);
      const linkedEvidence = await getEvidence(transaction, delta.evidenceId);
      if (current === null || linkedEvidence === null) {
        throw new InvalidDeltaApplicationError('Cannot link missing memory or evidence');
      }
      validateSourceLinks(current.id, sourceLinks, [], [delta.evidenceId]);
      await applySourceLinks(transaction, sourceLinks, idempotencyId);
      return;
    }
    case 'complete-action': {
      const current = await getAction(transaction, delta.targetId);
      if (current === null || !delta.explicitlyCompleted) {
        throw new InvalidDeltaApplicationError('Cannot complete an unverified action');
      }
      const provenance = await validateActionCompletionSource(transaction, application, delta);
      await updateAction(
        transaction,
        {
          ...current,
          lifecycle: 'completed',
          updatedAt: effectiveAt,
          statusChangedAt: effectiveAt,
        },
        `${idempotencyId}:action`,
      );
      await insertActionTransition(
        transaction,
        {
          id: provenance.transitionId,
          actionId: current.id,
          fromLifecycle: current.lifecycle,
          toLifecycle: 'completed',
          sourceMessageId: provenance.sourceMessageId,
          conversationId: provenance.conversationId,
          requestId: provenance.requestId,
          kind: 'explicit-user-completion',
          occurredAt: effectiveAt,
        },
        `${idempotencyId}:action-transition`,
      );
      return;
    }
    case 'archive-conversation': {
      const current = await getConversation(transaction, delta.targetId);
      if (current === null) {
        throw new InvalidDeltaApplicationError('Cannot archive missing conversation');
      }
      await updateConversation(
        transaction,
        {
          ...current,
          lifecycle: 'archived',
          archivedAt: effectiveAt,
          updatedAt: effectiveAt,
        },
        `${idempotencyId}:conversation`,
      );
      return;
    }
    case 'merge':
    case 'delete-memory':
      throw new InvalidDeltaApplicationError(
        'History-destructive memory operations require a dedicated confirmed workflow',
      );
  }
}

export async function applyConfirmedConflictResolution(
  transaction: RepositoryTransaction,
  application: ConfirmedConflictResolutionApplication,
): Promise<void> {
  requireNonEmpty(application.confirmationId, 'Confirmation ID');
  requireNonEmpty(application.idempotencyId, 'Idempotency ID');
  requireNonEmpty(application.successorId, 'Successor memory ID');
  requireNonEmpty(application.effectiveAt, 'Effective timestamp');
  const predecessorIds = sortedUnique(application.predecessorIds);
  if (
    predecessorIds.length === 0 ||
    predecessorIds.length !== application.predecessorIds.length ||
    application.candidate.changeKind !== 'replace' ||
    application.candidate.candidate.supersedesId == null ||
    !predecessorIds.includes(application.candidate.candidate.supersedesId) ||
    sortedUnique(application.candidate.conflictsWithIds).join('\u0000') !==
      predecessorIds.join('\u0000')
  ) {
    throw new InvalidDeltaApplicationError(
      'Conflict resolution must identify each confirmed predecessor exactly once',
    );
  }

  const resolution = confirmedConflictResolutionPayload(application);
  if (!(await claimMutation(
    transaction,
    application.idempotencyId,
    'governed-conflict-resolution',
    application.successorId,
    'resolve',
    resolution,
  ))) {
    return;
  }
  await consumeConfirmedMemoryResolution(transaction, {
    confirmationId: application.confirmationId,
    resolution,
    consumedAt: application.effectiveAt,
    consumedByIdempotencyId: application.idempotencyId,
  });

  const predecessors = await Promise.all(
    predecessorIds.map((id) => getMemory(transaction, id)),
  );
  if (
    predecessors.some(
      (item) =>
        item === null ||
        (item.lifecycle !== 'active' && item.lifecycle !== 'paused'),
    )
  ) {
    throw new InvalidDeltaApplicationError(
      'Every confirmed predecessor must still be active or paused',
    );
  }

  const sourceLinks = [...application.sourceLinks];
  const successorLinks = sourceLinks.filter(
    (source) => source.memoryItemId === application.successorId,
  );
  validateSourceLinks(
    application.successorId,
    successorLinks,
    application.candidate.candidate.sourceMessageIds,
  );
  for (const predecessorId of predecessorIds) {
    validateSourceLinks(
      predecessorId,
      sourceLinks.filter((source) => source.memoryItemId === predecessorId),
      application.candidate.candidate.sourceMessageIds,
    );
  }
  if (
    sourceLinks.some(
      (source) =>
        source.memoryItemId !== application.successorId &&
        !predecessorIds.includes(source.memoryItemId),
    )
  ) {
    throw new InvalidDeltaApplicationError('Conflict resolution contains an unrelated source link');
  }

  const successor: LocalMemoryItem = {
    ...application.candidate.candidate,
    id: application.successorId,
    lifecycle: 'active',
    createdAt: application.effectiveAt,
    confirmedAt: application.effectiveAt,
    lastSupportedAt: application.effectiveAt,
    statusChangedAt: application.effectiveAt,
    updatedAt: application.effectiveAt,
    sourceMessageIds: [...application.candidate.candidate.sourceMessageIds],
    sourceEvidenceIds: successorLinks.flatMap((source) =>
      source.evidenceId === null ? [] : [source.evidenceId],
    ),
  };
  await insertMemory(transaction, successor, `${application.idempotencyId}:successor`);
  for (const predecessor of predecessors as LocalMemoryItem[]) {
    await updateMemory(
      transaction,
      {
        ...predecessor,
        lifecycle: 'superseded',
        updatedAt: application.effectiveAt,
        statusChangedAt: application.effectiveAt,
      },
      `${application.idempotencyId}:predecessor:${predecessor.id}`,
    );
  }
  await applySourceLinks(transaction, sourceLinks, application.idempotencyId);
}

export async function applyConfirmedClarificationResolution(
  transaction: RepositoryTransaction,
  application: ConfirmedClarificationResolutionApplication,
): Promise<void> {
  requireNonEmpty(application.confirmationId, 'Confirmation ID');
  requireNonEmpty(application.idempotencyId, 'Idempotency ID');
  requireNonEmpty(application.successorId, 'Successor memory ID');
  requireNonEmpty(application.effectiveAt, 'Effective timestamp');
  const predecessorIds = sortedUnique(application.predecessorIds);
  if (
    predecessorIds.length === 0 ||
    predecessorIds.length !== application.predecessorIds.length ||
    application.candidate.changeKind !== 'replace' ||
    application.candidate.candidate.supersedesId == null ||
    !predecessorIds.includes(application.candidate.candidate.supersedesId) ||
    sortedUnique(application.candidate.conflictsWithIds).join('\u0000') !==
      predecessorIds.join('\u0000')
  ) {
    throw new InvalidDeltaApplicationError(
      'Clarification must identify each conflicting direction exactly once',
    );
  }

  const resolution = confirmedClarificationResolutionPayload(application);
  if (!(await claimMutation(
    transaction,
    application.idempotencyId,
    'governed-clarification-resolution',
    application.successorId,
    application.choice,
    resolution,
  ))) return;
  await consumeConfirmedMemoryResolution(transaction, {
    confirmationId: application.confirmationId,
    resolution,
    consumedAt: application.effectiveAt,
    consumedByIdempotencyId: application.idempotencyId,
  });

  const predecessors = await Promise.all(
    predecessorIds.map((id) => getMemory(transaction, id)),
  );
  if (predecessors.some((item) =>
    item === null || (item.lifecycle !== 'active' && item.lifecycle !== 'paused'))) {
    throw new InvalidDeltaApplicationError(
      'Every clarified direction must still be active or paused',
    );
  }

  const sourceLinks = [...application.sourceLinks];
  const successorLinks = sourceLinks.filter(
    (source) => source.memoryItemId === application.successorId,
  );
  validateSourceLinks(
    application.successorId,
    successorLinks,
    application.candidate.candidate.sourceMessageIds,
  );
  if (application.choice === 'coexist') {
    if (sourceLinks.length !== successorLinks.length) {
      throw new InvalidDeltaApplicationError('Coexistence cannot transition an existing direction');
    }
  } else {
    for (const predecessorId of predecessorIds) {
      validateSourceLinks(
        predecessorId,
        sourceLinks.filter((source) => source.memoryItemId === predecessorId),
        application.candidate.candidate.sourceMessageIds,
      );
    }
  }

  const successor: LocalMemoryItem = {
    ...application.candidate.candidate,
    id: application.successorId,
    lifecycle: 'active',
    supersedesId: application.choice === 'replace'
      ? application.candidate.candidate.supersedesId
      : null,
    createdAt: application.effectiveAt,
    confirmedAt: application.effectiveAt,
    lastSupportedAt: application.effectiveAt,
    statusChangedAt: application.effectiveAt,
    updatedAt: application.effectiveAt,
    sourceMessageIds: [...application.candidate.candidate.sourceMessageIds],
    sourceEvidenceIds: successorLinks.flatMap((source) =>
      source.evidenceId === null ? [] : [source.evidenceId],
    ),
  };
  await insertMemory(transaction, successor, `${application.idempotencyId}:successor`);
  if (application.choice !== 'coexist') {
    const lifecycle = application.choice === 'replace' ? 'superseded' : 'paused';
    for (const predecessor of predecessors as LocalMemoryItem[]) {
      await updateMemory(
        transaction,
        {
          ...predecessor,
          lifecycle,
          updatedAt: application.effectiveAt,
          statusChangedAt: application.effectiveAt,
        },
        `${application.idempotencyId}:predecessor:${predecessor.id}`,
      );
    }
  }
  await applySourceLinks(transaction, sourceLinks, application.idempotencyId);
}
