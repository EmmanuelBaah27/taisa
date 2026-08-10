import type {
  LocalAction,
  LocalConversation,
  LocalMemoryItem,
  LocalMemorySource,
} from '@taisa/shared';

import type { RepositoryTransaction } from '../../db/types';

import { getAction, updateAction } from '../../repositories/actionRepository';
import {
  getConversation,
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
import { requiresConfirmation } from './confirmationPolicy';

export type DeltaAuthorization =
  | { kind: 'user-confirmation'; confirmationId: string }
  | { kind: 'safe-automatic' };

export interface ConfirmedDeltaApplication {
  delta: GovernedMemoryDelta;
  authorization: DeltaAuthorization;
  idempotencyId: string;
  effectiveAt: string;
  newMemoryId?: string;
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

export async function applyConfirmedDelta(
  transaction: RepositoryTransaction,
  application: ConfirmedDeltaApplication,
): Promise<void> {
  requireNonEmpty(application.idempotencyId, 'Idempotency ID');
  requireNonEmpty(application.effectiveAt, 'Effective timestamp');
  if (application.authorization.kind === 'user-confirmation') {
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
  }

  const { delta, effectiveAt, idempotencyId, sourceLinks } = application;
  switch (delta.operation) {
    case 'propose': {
      const memoryId = requireNonEmpty(application.newMemoryId, 'New memory ID');
      validateSourceLinks(memoryId, sourceLinks, delta.candidate.sourceMessageIds);
      const memory: LocalMemoryItem = {
        ...delta.candidate,
        id: memoryId,
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
