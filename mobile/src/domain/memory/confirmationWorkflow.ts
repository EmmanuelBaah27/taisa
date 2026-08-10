import type { RepositoryTransaction } from '../../db/types';
import { getConversation, getMessage } from '../../repositories/conversationRepository';
import {
  confirmPendingMemoryConfirmation,
  consumeMemoryConfirmation,
  getMemoryConfirmation,
  insertPendingMemoryConfirmation,
} from '../../repositories/memoryConfirmationRepository';
import {
  canonicalizeMutationPayload,
  fingerprintMutationPayload,
} from '../../repositories/mutationFingerprint';
import type { GovernedMemoryDelta } from './admission';

export class MemoryConfirmationStateError extends Error {
  readonly code = 'MEMORY_CONFIRMATION_STATE';

  constructor(message: string) {
    super(message);
    this.name = 'MemoryConfirmationStateError';
  }
}

export class ConfirmationPayloadMismatchError extends Error {
  readonly code = 'CONFIRMATION_PAYLOAD_MISMATCH';

  constructor() {
    super('Confirmed memory resolution does not match the application payload');
    this.name = 'ConfirmationPayloadMismatchError';
  }
}

function requireNonEmpty(value: string, label: string): void {
  if (value.trim().length === 0) {
    throw new TypeError(`${label} must not be empty`);
  }
}

function constantTimeDigestEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

function proposalFromResolution(resolution: unknown): unknown {
  if (
    typeof resolution !== 'object' ||
    resolution === null ||
    Array.isArray(resolution) ||
    !Object.prototype.hasOwnProperty.call(resolution, 'proposal')
  ) {
    throw new ConfirmationPayloadMismatchError();
  }
  return (resolution as Record<string, unknown>).proposal;
}

export async function stageMemoryConfirmation(
  transaction: RepositoryTransaction,
  input: {
    confirmationId: string;
    proposal: GovernedMemoryDelta;
    conversationId: string;
    sourceMessageId: string;
    stagedAt: string;
    idempotencyId: string;
  },
): Promise<void> {
  requireNonEmpty(input.confirmationId, 'Confirmation ID');
  const [conversation, message] = await Promise.all([
    getConversation(transaction, input.conversationId),
    getMessage(transaction, input.sourceMessageId),
  ]);
  if (
    conversation === null ||
    message === null ||
    message.conversationId !== conversation.id ||
    message.role !== 'user' ||
    message.lifecycle !== 'submitted'
  ) {
    throw new MemoryConfirmationStateError(
      'Memory confirmation must be staged from a submitted local user message',
    );
  }
  await insertPendingMemoryConfirmation(
    transaction,
    {
      id: input.confirmationId,
      conversationId: input.conversationId,
      sourceMessageId: input.sourceMessageId,
      proposalJson: canonicalizeMutationPayload(input.proposal),
      proposalDigest: await fingerprintMutationPayload(input.proposal),
      stagedAt: input.stagedAt,
    },
    input.idempotencyId,
  );
}

export async function confirmMemoryResolution(
  transaction: RepositoryTransaction,
  input: {
    confirmationId: string;
    resolution: unknown;
    localUserAction: {
      id: string;
      kind: 'explicit-confirm';
      actedAt: string;
    };
    idempotencyId: string;
  },
): Promise<void> {
  requireNonEmpty(input.localUserAction.id, 'Local user action ID');
  const existing = await getMemoryConfirmation(transaction, input.confirmationId);
  if (existing === null) {
    throw new MemoryConfirmationStateError(
      'Only a pending memory confirmation can be explicitly confirmed',
    );
  }
  const embeddedProposalDigest = await fingerprintMutationPayload(
    proposalFromResolution(input.resolution),
  );
  if (!constantTimeDigestEqual(existing.proposalDigest, embeddedProposalDigest)) {
    throw new ConfirmationPayloadMismatchError();
  }
  await confirmPendingMemoryConfirmation(
    transaction,
    {
      id: input.confirmationId,
      resolutionJson: canonicalizeMutationPayload(input.resolution),
      resolutionDigest: await fingerprintMutationPayload(input.resolution),
      confirmedAt: input.localUserAction.actedAt,
      localUserActionId: input.localUserAction.id,
      localUserActionKind: input.localUserAction.kind,
      localUserActionAt: input.localUserAction.actedAt,
    },
    input.idempotencyId,
  );
}

export async function consumeConfirmedMemoryResolution(
  transaction: RepositoryTransaction,
  input: {
    confirmationId: string;
    resolution: unknown;
    consumedAt: string;
    consumedByIdempotencyId: string;
  },
): Promise<void> {
  const existing = await getMemoryConfirmation(transaction, input.confirmationId);
  if (existing === null || existing.status !== 'confirmed' || existing.resolutionDigest === null) {
    throw new MemoryConfirmationStateError(
      'Only a confirmed, unconsumed memory resolution can authorize application',
    );
  }
  const applicationDigest = await fingerprintMutationPayload(input.resolution);
  if (!constantTimeDigestEqual(existing.resolutionDigest, applicationDigest)) {
    throw new ConfirmationPayloadMismatchError();
  }
  await consumeMemoryConfirmation(
    transaction,
    {
      id: input.confirmationId,
      consumedAt: input.consumedAt,
      consumedByIdempotencyId: input.consumedByIdempotencyId,
    },
    `${input.consumedByIdempotencyId}:consume-confirmation`,
  );
}
