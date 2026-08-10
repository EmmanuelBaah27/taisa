import type {
  CoachingRequest,
  CoachingResponse,
  LocalConversation,
  LocalMemorySource,
  LocalMessage,
  UsageReceipt,
} from '@taisa/shared';

import {
  assembleCoachingContext,
  type ContextAssemblyLimits,
  type ContextManifest,
} from '../domain/context/assembleContext';
import {
  admitGatewayMemoryDelta,
  type GovernedMemoryDelta,
  type MemoryGovernanceState,
} from '../domain/memory/admission';
import {
  applyConfirmedConflictResolution,
  applyConfirmedDelta,
  confirmedConflictResolutionPayload,
  confirmedDeltaResolutionPayload,
  type ConfirmedConflictResolutionApplication,
  type ConfirmedDeltaApplication,
} from '../domain/memory/applyDelta';
import {
  confirmMemoryResolution,
  stageMemoryConfirmation,
} from '../domain/memory/confirmationWorkflow';
import type {
  ExclusiveTransactionConnection,
  RepositoryConnection,
  RepositoryTransaction,
} from '../db/types';
import { withRepositoryTransaction } from '../db/types';
import { listActions } from '../repositories/actionRepository';
import {
  getCoachingRequest,
  insertCoachingRequest,
  insertUsageReceipt,
  type LocalCoachingRequest,
  updateCoachingRequest,
} from '../repositories/coachingRequestRepository';
import {
  getConversation,
  getMessage,
  insertConversation,
  insertMessage,
  listConversations,
  listRecentMessages,
  updateMessage,
} from '../repositories/conversationRepository';
import { listEvidence, searchEvidence } from '../repositories/evidenceRepository';
import { getMemoryConfirmation } from '../repositories/memoryConfirmationRepository';
import { listMemories } from '../repositories/memoryRepository';
import { getProfile } from '../repositories/profileRepository';

const DEFAULT_CONTEXT_LIMITS: ContextAssemblyLimits = {
  maxCharacters: 20_000,
  maxEstimatedTokens: 20_000,
  memoryCandidateLimit: 50,
  evidenceCandidateLimit: 32,
};

export interface TranscriptionRequest {
  requestId: string;
  audioUri: string;
  durationSeconds: number;
}

export interface TranscriptionResult {
  transcript: string;
  durationSeconds: number;
  usage: UsageReceipt;
}

export interface PrivateCaptureDependencies {
  database: ExclusiveTransactionConnection;
  coach(request: CoachingRequest): Promise<CoachingResponse>;
  transcribe(request: TranscriptionRequest): Promise<TranscriptionResult>;
  now(): string;
  createId(): string;
  getProfileId(): Promise<string>;
  contextLimits?: ContextAssemblyLimits;
}

export interface PrivateSaveResult {
  status: 'private';
  conversationId: string;
  messageId: string;
}

export interface CompletedSubmissionResult {
  status: 'completed';
  requestId: string;
  messageId: string;
  assistantMessageId: string;
  pendingProposalIds: string[];
  pendingProposals: PendingProposal[];
}

export interface PendingProposal {
  id: string;
  summary: string;
}

export interface TranscriptConfirmationResult {
  status: 'transcript-confirmation-required';
  requestId: string;
  messageId: string;
  transcript: string;
}

export type SubmissionResult = CompletedSubmissionResult | TranscriptConfirmationResult;

export interface PrivateCaptureService {
  savePrivateDraft(input: { conversationId: string; content: string }): Promise<PrivateSaveResult>;
  submitText(input: { conversationId: string; content: string }): Promise<CompletedSubmissionResult>;
  submitVoice(input: {
    conversationId: string;
    audioUri: string;
    durationSeconds: number;
  }): Promise<TranscriptConfirmationResult>;
  updateTranscript(input: { requestId: string; transcript: string }): Promise<void>;
  confirmTranscript(input: { requestId: string }): Promise<CompletedSubmissionResult>;
  retrySubmission(requestId: string): Promise<SubmissionResult>;
  confirmProposal(input: {
    confirmationId: string;
    localUserActionId: string;
    actedAt: string;
  }): Promise<void>;
}

export class SubmissionFailedError extends Error {
  readonly code = 'SUBMISSION_FAILED';

  constructor(
    readonly requestId: string,
    readonly phase: 'transcription' | 'coaching',
  ) {
    super(phase === 'transcription'
      ? 'The recording could not be transcribed. Your recording is still on this device.'
      : 'Taisa could not complete this submission. Your thought is still on this device.');
    this.name = 'SubmissionFailedError';
  }
}

export class LocalSubmissionStateError extends Error {
  readonly code = 'LOCAL_SUBMISSION_STATE';

  constructor(message: string) {
    super(message);
    this.name = 'LocalSubmissionStateError';
  }
}

function requireContent(value: string, label: string): string {
  const normalized = value.trim();
  if (normalized.length === 0) throw new TypeError(`${label} must not be empty`);
  return normalized;
}

function safeFtsQuery(value: string): string {
  const tokens = value
    .normalize('NFKC')
    .split(/\s+/u)
    .map((token) => token.replace(/["*:^(){}\[\]]/gu, '').trim())
    .filter(Boolean)
    .slice(0, 16);
  return tokens.length === 0 ? '""' : tokens.map((token) => `"${token}"`).join(' OR ');
}

function messageFor(
  id: string,
  conversationId: string,
  content: string,
  lifecycle: LocalMessage['lifecycle'],
  requestId: string | null,
  timestamp: string,
): LocalMessage {
  return {
    id,
    conversationId,
    parentMessageId: null,
    role: 'user',
    content,
    lifecycle,
    requestId,
    createdAt: timestamp,
    updatedAt: timestamp,
  };
}

async function ensureConversation(
  transaction: RepositoryTransaction,
  id: string,
  timestamp: string,
  titleSource: string,
): Promise<void> {
  if (await getConversation(transaction, id)) return;
  const title = titleSource.trim().slice(0, 80) || 'Voice reflection';
  const conversation: LocalConversation = {
    id,
    title,
    lifecycle: 'active',
    createdAt: timestamp,
    updatedAt: timestamp,
    archivedAt: null,
  };
  await insertConversation(transaction, conversation, `${id}:create`);
}

function contextRepositories(database: RepositoryConnection) {
  return {
    getProfile: (profileId: string) => getProfile(database, profileId),
    listRecentMessages: (conversationId: string, limit: number) =>
      listRecentMessages(database, conversationId, limit),
    listMemoryCandidates: (lifecycles: Parameters<typeof listMemories>[1], limit: number) =>
      listMemories(database, lifecycles, limit),
    listEvidenceCandidates: (query: string, limit: number) =>
      searchEvidence(database, safeFtsQuery(query), limit),
  };
}

async function governanceState(
  database: RepositoryConnection,
): Promise<MemoryGovernanceState> {
  const [memory, actions, conversations, evidence] = await Promise.all([
    listMemories(database),
    listActions(database),
    listConversations(database),
    listEvidence(database),
  ]);
  return { memory, actions, conversations, evidence };
}

function sourceLink(
  id: string,
  memoryItemId: string,
  messageId: string,
  linkedAt: string,
): LocalMemorySource {
  return { id, memoryItemId, messageId, evidenceId: null, linkedAt };
}

export function createPrivateCaptureService(
  dependencies: PrivateCaptureDependencies,
): PrivateCaptureService {
  const limits = dependencies.contextLimits ?? DEFAULT_CONTEXT_LIMITS;

  async function markFailed(
    requestId: string,
    phase: 'transcription' | 'coaching',
  ): Promise<never> {
    const timestamp = dependencies.now();
    await withRepositoryTransaction(dependencies.database, async (transaction) => {
      const request = await getCoachingRequest(transaction, requestId);
      if (request === null) throw new LocalSubmissionStateError('Submission no longer exists');
      const message = await getMessage(transaction, request.userMessageId);
      if (message === null) throw new LocalSubmissionStateError('Submission message no longer exists');
      const status = phase === 'transcription' ? 'transcription-failed' : 'coaching-failed';
      const errorCode = phase === 'transcription' ? 'TRANSCRIPTION_FAILED' : 'COACHING_FAILED';
      await updateMessage(
        transaction,
        { ...message, lifecycle: 'failed', updatedAt: timestamp },
        `${request.id}:attempt:${request.attemptCount}:message-failed`,
      );
      await updateCoachingRequest(
        transaction,
        { ...request, status, errorCode, updatedAt: timestamp },
        `${request.id}:attempt:${request.attemptCount}:${status}`,
      );
    });
    throw new SubmissionFailedError(requestId, phase);
  }

  async function stageResponseProposals(
    transaction: RepositoryTransaction,
    request: LocalCoachingRequest,
    sourceMessage: LocalMessage,
    response: CoachingResponse,
    effectiveAt: string,
  ): Promise<PendingProposal[]> {
    const pendingProposals: PendingProposal[] = [];
    for (let index = 0; index < response.proposals.length; index += 1) {
      const providerProposal = response.proposals[index];
      const admission = admitGatewayMemoryDelta(
        providerProposal,
        await governanceState(transaction),
        { conversationId: request.conversationId, sourceMessage },
      );
      if (admission.status === 'rejected' || admission.status === 'archive-only') continue;
      const delta = admission.status === 'clarification-required'
        ? admission.candidate
        : admission.delta;
      const proposalId = `${request.id}:proposal:${index}`;
      if (
        admission.status === 'confirmation-required' ||
        admission.status === 'clarification-required'
      ) {
        await stageMemoryConfirmation(transaction, {
          confirmationId: proposalId,
          proposal: delta,
          conversationId: request.conversationId,
          sourceMessageId: sourceMessage.id,
          stagedAt: effectiveAt,
          idempotencyId: `${proposalId}:stage`,
        });
        pendingProposals.push({
          id: proposalId,
          summary: delta.operation === 'propose' ? delta.candidate.statement : delta.reason,
        });
        continue;
      }

      const targetId = delta.operation === 'support' ? delta.targetId : '';
      const links = targetId === '' ? [] : [sourceLink(
        `${proposalId}:source:${targetId}`,
        targetId,
        sourceMessage.id,
        effectiveAt,
      )];
      await applyConfirmedDelta(transaction, {
        delta,
        authorization: { kind: 'safe-automatic' },
        idempotencyId: `${proposalId}:apply`,
        effectiveAt,
        sourceLinks: links,
        trustedContext: {
          conversationId: request.conversationId,
          sourceMessageId: sourceMessage.id,
          requestId: request.id,
        },
      });
    }
    return pendingProposals;
  }

  async function runCoaching(requestId: string): Promise<CompletedSubmissionResult> {
    const storedRequest = await getCoachingRequest(dependencies.database, requestId);
    if (storedRequest === null) throw new LocalSubmissionStateError('Submission no longer exists');
    const storedMessage = await getMessage(dependencies.database, storedRequest.userMessageId);
    if (storedMessage === null) throw new LocalSubmissionStateError('Submission message no longer exists');
    const profileId = await dependencies.getProfileId();
    let assembled;
    try {
      assembled = await assembleCoachingContext(
        {
          requestId: storedRequest.id,
          submittedAt: storedRequest.submittedAt,
          submittedThought: storedMessage.content,
          conversationId: storedRequest.conversationId,
          profileId,
          directEvidenceIds: [],
          directSourceMessageIds: [storedMessage.id],
          relatedGoalIds: [],
          relatedActionIds: [],
        },
        contextRepositories(dependencies.database),
        limits,
      );
    } catch {
      return markFailed(requestId, 'coaching');
    }

    let response: CoachingResponse;
    try {
      response = await dependencies.coach(assembled.request);
      if (response.requestId !== storedRequest.id) {
        throw new Error('Mismatched response identifier');
      }
    } catch {
      return markFailed(requestId, 'coaching');
    }

    const timestamp = dependencies.now();
    const assistantMessageId = dependencies.createId();
    try {
      return await withRepositoryTransaction(dependencies.database, async (transaction) => {
        const request = await getCoachingRequest(transaction, requestId);
        const userMessage = request === null ? null : await getMessage(transaction, request.userMessageId);
        if (request === null || userMessage === null) {
          throw new LocalSubmissionStateError('Submission state changed before completion');
        }
        const submittedMessage: LocalMessage = {
          ...userMessage,
          lifecycle: 'submitted',
          updatedAt: timestamp,
        };
        await updateMessage(
          transaction,
          submittedMessage,
          `${request.id}:attempt:${request.attemptCount}:message-submitted`,
        );
        const assistantMessage: LocalMessage = {
          id: assistantMessageId,
          conversationId: request.conversationId,
          parentMessageId: userMessage.id,
          role: 'assistant',
          content: response.reply,
          lifecycle: 'received',
          requestId: null,
          createdAt: timestamp,
          updatedAt: timestamp,
        };
        await insertMessage(
          transaction,
          assistantMessage,
          `${request.id}:assistant-message`,
        );
        await insertUsageReceipt(
          transaction,
          {
            id: `${request.id}:coaching-usage`,
            requestId: request.id,
            receipt: response.usage,
            recordedAt: timestamp,
          },
          `${request.id}:coaching-usage`,
        );
        const pendingProposals = await stageResponseProposals(
          transaction,
          request,
          submittedMessage,
          response,
          timestamp,
        );
        await updateCoachingRequest(
          transaction,
          {
            ...request,
            status: 'completed',
            assistantMessageId,
            stance: response.stance,
            contextManifestJson: JSON.stringify(assembled.manifest),
            errorCode: null,
            updatedAt: timestamp,
          },
          `${request.id}:attempt:${request.attemptCount}:completed`,
        );
        return {
          status: 'completed',
          requestId: request.id,
          messageId: userMessage.id,
          assistantMessageId,
          pendingProposalIds: pendingProposals.map((proposal) => proposal.id),
          pendingProposals,
        };
      });
    } catch {
      return markFailed(requestId, 'coaching');
    }
  }

  async function runTranscription(requestId: string): Promise<TranscriptConfirmationResult> {
    const request = await getCoachingRequest(dependencies.database, requestId);
    if (
      request === null ||
      request.kind !== 'voice' ||
      request.transcriptionRequestId === null ||
      request.audioUri === null ||
      request.audioDurationSeconds === null
    ) {
      throw new LocalSubmissionStateError('Voice submission is incomplete');
    }
    let result: TranscriptionResult;
    try {
      result = await dependencies.transcribe({
        requestId: request.transcriptionRequestId,
        audioUri: request.audioUri,
        durationSeconds: request.audioDurationSeconds,
      });
      requireContent(result.transcript, 'Transcript');
    } catch {
      return markFailed(requestId, 'transcription');
    }
    const timestamp = dependencies.now();
    try {
      return await withRepositoryTransaction(dependencies.database, async (transaction) => {
        const current = await getCoachingRequest(transaction, requestId);
        const message = current === null ? null : await getMessage(transaction, current.userMessageId);
        if (current === null || message === null || current.transcriptionRequestId === null) {
          throw new LocalSubmissionStateError('Voice submission state changed');
        }
        const transcript = result.transcript.trim();
        await updateMessage(
          transaction,
          { ...message, content: transcript, lifecycle: 'pending', updatedAt: timestamp },
          `${current.id}:attempt:${current.attemptCount}:transcript`,
        );
        await insertUsageReceipt(
          transaction,
          {
            id: `${current.transcriptionRequestId}:usage`,
            requestId: current.transcriptionRequestId,
            receipt: result.usage,
            recordedAt: timestamp,
          },
          `${current.transcriptionRequestId}:usage`,
        );
        await updateCoachingRequest(
          transaction,
          {
            ...current,
            status: 'transcript-confirmation-required',
            audioDurationSeconds: result.durationSeconds,
            errorCode: null,
            updatedAt: timestamp,
          },
          `${current.id}:attempt:${current.attemptCount}:transcript-complete`,
        );
        return {
          status: 'transcript-confirmation-required',
          requestId: current.id,
          messageId: current.userMessageId,
          transcript,
        };
      });
    } catch {
      return markFailed(requestId, 'transcription');
    }
  }

  return {
    async savePrivateDraft(input) {
      const content = requireContent(input.content, 'Private draft');
      const timestamp = dependencies.now();
      const messageId = dependencies.createId();
      await withRepositoryTransaction(dependencies.database, async (transaction) => {
        await ensureConversation(transaction, input.conversationId, timestamp, content);
        await insertMessage(
          transaction,
          messageFor(messageId, input.conversationId, content, 'private', null, timestamp),
          `${messageId}:private-save`,
        );
      });
      return { status: 'private', conversationId: input.conversationId, messageId };
    },

    async submitText(input) {
      const content = requireContent(input.content, 'Submitted thought');
      const timestamp = dependencies.now();
      const requestId = dependencies.createId();
      const messageId = dependencies.createId();
      await withRepositoryTransaction(dependencies.database, async (transaction) => {
        await ensureConversation(transaction, input.conversationId, timestamp, content);
        await insertMessage(
          transaction,
          messageFor(messageId, input.conversationId, content, 'pending', requestId, timestamp),
          `${requestId}:user-message`,
        );
        await insertCoachingRequest(
          transaction,
          {
            id: requestId,
            conversationId: input.conversationId,
            userMessageId: messageId,
            transcriptionRequestId: null,
            kind: 'text',
            status: 'coaching-pending',
            audioUri: null,
            audioDurationSeconds: null,
            transcriptConfirmedAt: null,
            assistantMessageId: null,
            stance: null,
            contextManifestJson: null,
            errorCode: null,
            attemptCount: 1,
            submittedAt: timestamp,
            createdAt: timestamp,
            updatedAt: timestamp,
          },
          `${requestId}:request`,
        );
      });
      return runCoaching(requestId);
    },

    async submitVoice(input) {
      if (!Number.isFinite(input.durationSeconds) || input.durationSeconds <= 0) {
        throw new TypeError('Recording duration must be a positive number');
      }
      const audioUri = requireContent(input.audioUri, 'Audio URI');
      const timestamp = dependencies.now();
      const requestId = dependencies.createId();
      const messageId = dependencies.createId();
      const transcriptionRequestId = dependencies.createId();
      await withRepositoryTransaction(dependencies.database, async (transaction) => {
        await ensureConversation(transaction, input.conversationId, timestamp, 'Voice reflection');
        await insertMessage(
          transaction,
          messageFor(messageId, input.conversationId, '', 'pending', requestId, timestamp),
          `${requestId}:user-message`,
        );
        await insertCoachingRequest(
          transaction,
          {
            id: requestId,
            conversationId: input.conversationId,
            userMessageId: messageId,
            transcriptionRequestId,
            kind: 'voice',
            status: 'transcription-pending',
            audioUri,
            audioDurationSeconds: input.durationSeconds,
            transcriptConfirmedAt: null,
            assistantMessageId: null,
            stance: null,
            contextManifestJson: null,
            errorCode: null,
            attemptCount: 1,
            submittedAt: timestamp,
            createdAt: timestamp,
            updatedAt: timestamp,
          },
          `${requestId}:request`,
        );
      });
      return runTranscription(requestId);
    },

    async updateTranscript(input) {
      const transcript = requireContent(input.transcript, 'Transcript');
      const timestamp = dependencies.now();
      await withRepositoryTransaction(dependencies.database, async (transaction) => {
        const request = await getCoachingRequest(transaction, input.requestId);
        if (request === null || request.status !== 'transcript-confirmation-required') {
          throw new LocalSubmissionStateError('Transcript is not available for editing');
        }
        const message = await getMessage(transaction, request.userMessageId);
        if (message === null) throw new LocalSubmissionStateError('Transcript message is missing');
        await updateMessage(
          transaction,
          { ...message, content: transcript, updatedAt: timestamp },
          `${request.id}:transcript-edit:${dependencies.createId()}`,
        );
      });
    },

    async confirmTranscript(input) {
      const timestamp = dependencies.now();
      await withRepositoryTransaction(dependencies.database, async (transaction) => {
        const request = await getCoachingRequest(transaction, input.requestId);
        if (request === null || request.status !== 'transcript-confirmation-required') {
          throw new LocalSubmissionStateError('Transcript requires explicit confirmation');
        }
        await updateCoachingRequest(
          transaction,
          {
            ...request,
            status: 'coaching-pending',
            transcriptConfirmedAt: timestamp,
            errorCode: null,
            updatedAt: timestamp,
          },
          `${request.id}:transcript-confirmed`,
        );
      });
      return runCoaching(input.requestId);
    },

    async retrySubmission(requestId) {
      const timestamp = dependencies.now();
      const request = await withRepositoryTransaction(
        dependencies.database,
        async (transaction) => {
          const current = await getCoachingRequest(transaction, requestId);
          if (
            current === null ||
            (current.status !== 'transcription-failed' && current.status !== 'coaching-failed')
          ) {
            throw new LocalSubmissionStateError('Only a failed submission can be retried');
          }
          const message = await getMessage(transaction, current.userMessageId);
          if (message === null) throw new LocalSubmissionStateError('Submission message is missing');
          const attemptCount = current.attemptCount + 1;
          const status = current.status === 'transcription-failed'
            ? 'transcription-pending'
            : 'coaching-pending';
          await updateMessage(
            transaction,
            { ...message, lifecycle: 'pending', updatedAt: timestamp },
            `${current.id}:attempt:${attemptCount}:message-pending`,
          );
          const updated: LocalCoachingRequest = {
            ...current,
            status,
            attemptCount,
            errorCode: null,
            updatedAt: timestamp,
          };
          await updateCoachingRequest(
            transaction,
            updated,
            `${current.id}:attempt:${attemptCount}:pending`,
          );
          return updated;
        },
      );
      return request.status === 'transcription-pending'
        ? runTranscription(request.id)
        : runCoaching(request.id);
    },

    async confirmProposal(input) {
      requireContent(input.localUserActionId, 'Local user action ID');
      await withRepositoryTransaction(dependencies.database, async (transaction) => {
        const confirmation = await getMemoryConfirmation(transaction, input.confirmationId);
        if (confirmation === null) {
          throw new LocalSubmissionStateError('Memory proposal no longer exists');
        }
        if (confirmation.status === 'consumed') return;
        const delta = JSON.parse(confirmation.proposalJson) as GovernedMemoryDelta;
        if (
          delta.operation === 'propose' &&
          (delta.changeKind === 'replace' || delta.conflictsWithIds.length > 0)
        ) {
          const successorId = `${confirmation.id}:memory`;
          const predecessorIds = [...delta.conflictsWithIds];
          const sourceLinks = [successorId, ...predecessorIds].map((memoryId) => sourceLink(
            `${confirmation.id}:source:${memoryId}`,
            memoryId,
            confirmation.sourceMessageId,
            input.actedAt,
          ));
          const application: ConfirmedConflictResolutionApplication = {
            confirmationId: confirmation.id,
            idempotencyId: `${confirmation.id}:apply`,
            effectiveAt: input.actedAt,
            successorId,
            candidate: delta,
            predecessorIds,
            sourceLinks,
          };
          const resolution = confirmedConflictResolutionPayload(application);
          await confirmMemoryResolution(transaction, {
            confirmationId: confirmation.id,
            resolution,
            localUserAction: {
              id: input.localUserActionId,
              kind: 'explicit-confirm',
              actedAt: input.actedAt,
            },
            idempotencyId: `${confirmation.id}:confirm`,
          });
          await applyConfirmedConflictResolution(transaction, application);
          return;
        }

        const memoryId = delta.operation === 'propose'
          ? `${confirmation.id}:memory`
          : delta.operation === 'transition' || delta.operation === 'support'
            ? delta.targetId
            : '';
        const sourceLinks = memoryId === '' ? [] : [sourceLink(
          `${confirmation.id}:source:${memoryId}`,
          memoryId,
          confirmation.sourceMessageId,
          input.actedAt,
        )];
        const application: ConfirmedDeltaApplication = {
          delta,
          authorization: { kind: 'confirmed-record', confirmationId: confirmation.id },
          idempotencyId: `${confirmation.id}:apply`,
          effectiveAt: input.actedAt,
          newMemoryId: delta.operation === 'propose' ? memoryId : undefined,
          sourceLinks,
        };
        const resolution = confirmedDeltaResolutionPayload(application);
        await confirmMemoryResolution(transaction, {
          confirmationId: confirmation.id,
          resolution,
          localUserAction: {
            id: input.localUserActionId,
            kind: 'explicit-confirm',
            actedAt: input.actedAt,
          },
          idempotencyId: `${confirmation.id}:confirm`,
        });
        await applyConfirmedDelta(transaction, application);
      });
    },
  };
}

export type { ContextManifest };
