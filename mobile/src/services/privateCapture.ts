import type {
  CoachingRequest,
  CoachingResponse,
  OutcomeDelta,
  LocalAction,
  LocalConversation,
  LocalGoal,
  LocalMemoryItem,
  LocalMemorySource,
  LocalMessage,
  UsageReceipt,
} from '@taisa/shared';
import { COACHING_GATEWAY_LIMITS } from '@taisa/shared';

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
  applyConfirmedClarificationResolution,
  applyConfirmedDelta,
  confirmedClarificationResolutionPayload,
  confirmedDeltaResolutionPayload,
  type ConfirmedClarificationResolutionApplication,
  type ConfirmedDeltaApplication,
} from '../domain/memory/applyDelta';
import {
  confirmMemoryResolution,
  consumeConfirmedMemoryResolution,
  stageMemoryConfirmation,
} from '../domain/memory/confirmationWorkflow';
import type {
  ExclusiveTransactionConnection,
  RepositoryConnection,
  RepositoryTransaction,
} from '../db/types';
import { withRepositoryTransaction } from '../db/types';
import { insertAction, listActions } from '../repositories/actionRepository';
import { insertGoal, listGoals } from '../repositories/goalRepository';
import {
  getCoachingRequest,
  insertCoachingRequest,
  insertUsageReceipt,
  listCoachingRequestsByConversation,
  retireAbandonedAudioReferences,
  type LocalCoachingRequest,
  updateCoachingRequest,
} from '../repositories/coachingRequestRepository';
import {
  enqueueAudioCleanup,
  isAudioUriReferencedByActiveCoachingRequest,
  listDeletableAudioCleanupQueue,
  markAudioCleanupAttempt,
  removeAudioCleanup,
} from '../repositories/audioCleanupRepository';
import {
  getConversation,
  getMessage,
  insertConversation,
  insertMessage,
  listConversations,
  listRecentMessages,
  updateMessage,
} from '../repositories/conversationRepository';
import {
  insertEvidence,
  listEvidence,
  listEvidenceByRelationships,
  searchEvidence,
} from '../repositories/evidenceRepository';
import {
  getMemoryConfirmation,
  listMemoryConfirmationsByConversation,
  type LocalMemoryConfirmation,
} from '../repositories/memoryConfirmationRepository';
import { listMemories } from '../repositories/memoryRepository';
import { getProfile } from '../repositories/profileRepository';
import type { AudioFileStore } from './audioFileStore';

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
  audioFiles: AudioFileStore;
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
  kind: 'proposal' | 'clarification';
  question: string | null;
  status: 'pending' | 'confirmed';
}

export type ClarificationChoice = 'replace' | 'pause' | 'coexist';

export interface HydratedConversationState {
  requestId: string | null;
  messageId: string | null;
  requestStatus: LocalCoachingRequest['status'] | null;
  transcript: string;
  pendingProposals: PendingProposal[];
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
  submitText(input: {
    conversationId: string;
    content: string;
    intentId?: string;
  }): Promise<CompletedSubmissionResult>;
  submitVoice(input: {
    conversationId: string;
    audioUri: string;
    durationSeconds: number;
    intentId?: string;
  }): Promise<TranscriptConfirmationResult>;
  updateTranscript(input: { requestId: string; transcript: string }): Promise<void>;
  confirmTranscript(input: { requestId: string }): Promise<CompletedSubmissionResult>;
  retrySubmission(requestId: string): Promise<SubmissionResult>;
  confirmProposal(input: {
    confirmationId: string;
    localUserActionId: string;
    actedAt: string;
  }): Promise<void>;
  resolveClarification(input: {
    confirmationId: string;
    choice: ClarificationChoice;
    localUserActionId: string;
    actedAt: string;
  }): Promise<void>;
  hydrateConversation(conversationId: string): Promise<HydratedConversationState>;
  drainAudioCleanupQueue(): Promise<void>;
  discardRecording(uri: string): Promise<void>;
  abandonVoiceSubmission(requestId: string): Promise<void>;
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

export class SubmissionValidationError extends Error {
  readonly code = 'SUBMISSION_VALIDATION';

  constructor() {
    super('This submission is too long. Edit it on this device before submitting again.');
    this.name = 'SubmissionValidationError';
  }
}

function requireContent(value: string, label: string): string {
  const normalized = value.trim();
  if (normalized.length === 0) throw new TypeError(`${label} must not be empty`);
  return normalized;
}

function validateCoachingContent(value: string, label: string): string {
  const normalized = requireContent(value, label);
  if (normalized.length > COACHING_GATEWAY_LIMITS.maxTextLength) {
    throw new SubmissionValidationError();
  }
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

function contextRepositories(
  database: RepositoryConnection,
  activeGoals: readonly LocalGoal[] = [],
  openActions: readonly LocalAction[] = [],
) {
  const relatedGoalIds = activeGoals.map((goal) => goal.id);
  const relatedActionIds = openActions.map((action) => action.id);
  const outcomeMemory: LocalMemoryItem[] = [
    ...activeGoals.map((goal): LocalMemoryItem => ({
      id: goal.id,
      type: 'goal',
      statement: [goal.title, goal.description].filter(Boolean).join(': '),
      provenance: 'user-confirmed', lifecycle: 'active', confidence: 'established',
      createdAt: goal.createdAt, confirmedAt: goal.statusChangedAt,
      lastSupportedAt: goal.updatedAt, statusChangedAt: goal.statusChangedAt,
      sourceMessageIds: goal.sourceMessageId === null ? [] : [goal.sourceMessageId],
      sourceEvidenceIds: [], updatedAt: goal.updatedAt,
      supersedesId: goal.supersedesId,
    })),
    ...openActions.map((action): LocalMemoryItem => ({
      id: action.id,
      type: 'commitment',
      statement: [action.title, action.description].filter(Boolean).join(': '),
      provenance: 'user-confirmed', lifecycle: 'active', confidence: 'established',
      createdAt: action.createdAt, confirmedAt: action.statusChangedAt,
      lastSupportedAt: action.updatedAt, statusChangedAt: action.statusChangedAt,
      sourceMessageIds: action.sourceMessageId === null ? [] : [action.sourceMessageId],
      sourceEvidenceIds: [], updatedAt: action.updatedAt,
      supersedesId: action.supersedesId,
    })),
  ];
  return {
    getProfile: (profileId: string) => getProfile(database, profileId),
    listRecentMessages: (conversationId: string, limit: number) =>
      listRecentMessages(database, conversationId, limit),
    listMemoryCandidates: async (lifecycles: Parameters<typeof listMemories>[1], limit: number) => {
      const stored = await listMemories(database, lifecycles, limit);
      return mergeContextMemoryCandidates(
        outcomeMemory.filter((item) => item.type === 'goal'),
        outcomeMemory.filter((item) => item.type === 'commitment'),
        stored,
        limit,
      );
    },
    listEvidenceCandidates: async (query: string, limit: number) => {
      const [lexical, related] = await Promise.all([
        searchEvidence(database, safeFtsQuery(query), limit),
        listEvidenceByRelationships(database, relatedGoalIds, relatedActionIds, limit),
      ]);
      const unique = new Map([...related, ...lexical].map((item) => [item.id, item]));
      return [...unique.values()].slice(0, limit);
    },
  };
}

export function mergeContextMemoryCandidates(
  goals: readonly LocalMemoryItem[],
  actions: readonly LocalMemoryItem[],
  memory: readonly LocalMemoryItem[],
  limit: number,
): LocalMemoryItem[] {
  const groups = [goals, actions, memory];
  const selected: LocalMemoryItem[] = [];
  const seen = new Set<string>();
  for (let index = 0; selected.length < limit; index += 1) {
    let found = false;
    for (const group of groups) {
      const item = group[index];
      if (item === undefined) continue;
      found = true;
      if (!seen.has(item.id)) {
        seen.add(item.id);
        selected.push(item);
        if (selected.length === limit) break;
      }
    }
    if (!found) break;
  }
  return selected;
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
  const inFlightIntents = new Map<string, Promise<SubmissionResult>>();
  const inFlightRequests = new Map<string, Promise<SubmissionResult>>();
  const inFlightAudioCleanups = new Map<string, Promise<void>>();
  let inFlightAudioCleanupDrain: Promise<void> | null = null;

  async function enqueueRecordingCleanup(audioUri: string): Promise<void> {
    await withRepositoryTransaction(dependencies.database, (transaction) =>
      enqueueAudioCleanup(transaction, {
        audioUri,
        enqueuedAt: dependencies.now(),
      }));
  }

  async function finishRecordingCleanup(audioUri: string): Promise<void> {
    await withRepositoryTransaction(dependencies.database, async (transaction) => {
      await retireAbandonedAudioReferences(transaction, audioUri);
      await removeAudioCleanup(transaction, audioUri);
    });
  }

  async function recordRecordingCleanupFailure(audioUri: string): Promise<void> {
    await withRepositoryTransaction(dependencies.database, async (transaction) => {
      await markAudioCleanupAttempt(transaction, {
        audioUri,
        attemptedAt: dependencies.now(),
        errorCode: 'AUDIO_DELETE_FAILED',
      });
      await retireAbandonedAudioReferences(transaction, audioUri);
    });
  }

  async function attemptQueuedRecordingCleanup(audioUri: string): Promise<void> {
    if (await isAudioUriReferencedByActiveCoachingRequest(dependencies.database, audioUri)) {
      return;
    }
    try {
      await dependencies.audioFiles.deleteRecording(audioUri);
    } catch {
      await recordRecordingCleanupFailure(audioUri);
      return;
    }
    await finishRecordingCleanup(audioUri);
  }

  function joinRecordingCleanup(audioUri: string, enqueueFirst: boolean): Promise<void> {
    const current = inFlightAudioCleanups.get(audioUri);
    if (current !== undefined) return current;
    const cleanup = (async () => {
      if (enqueueFirst) await enqueueRecordingCleanup(audioUri);
      await attemptQueuedRecordingCleanup(audioUri);
    })();
    inFlightAudioCleanups.set(audioUri, cleanup);
    void cleanup.finally(() => {
      if (inFlightAudioCleanups.get(audioUri) === cleanup) {
        inFlightAudioCleanups.delete(audioUri);
      }
    }).catch(() => {});
    return cleanup;
  }

  function queueAndAttemptRecordingCleanup(audioUri: string): Promise<void> {
    return joinRecordingCleanup(audioUri, true);
  }

  function drainAudioCleanupQueue(): Promise<void> {
    if (inFlightAudioCleanupDrain !== null) return inFlightAudioCleanupDrain;
    const drain = (async () => {
      const entries = await listDeletableAudioCleanupQueue(dependencies.database, 20);
      for (const entry of entries) {
        await joinRecordingCleanup(entry.audioUri, false);
      }
    })();
    inFlightAudioCleanupDrain = drain;
    void drain.finally(() => {
      if (inFlightAudioCleanupDrain === drain) inFlightAudioCleanupDrain = null;
    }).catch(() => {});
    return drain;
  }

  function withInFlightIntent<T extends SubmissionResult>(
    intentId: string,
    operation: () => Promise<T>,
  ): Promise<T> {
    const current = inFlightIntents.get(intentId);
    if (current !== undefined) return current as Promise<T>;
    const promise = operation();
    inFlightIntents.set(intentId, promise);
    void promise.finally(() => {
      if (inFlightIntents.get(intentId) === promise) inFlightIntents.delete(intentId);
    }).catch(() => {});
    return promise;
  }

  function withInFlightRequest<T extends SubmissionResult>(
    requestId: string,
    operation: () => Promise<T>,
  ): Promise<T> {
    const current = inFlightRequests.get(requestId);
    if (current !== undefined) return current as Promise<T>;
    const promise = operation();
    inFlightRequests.set(requestId, promise);
    void promise.finally(() => {
      if (inFlightRequests.get(requestId) === promise) inFlightRequests.delete(requestId);
    }).catch(() => {});
    return promise;
  }

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
      const proposalId = `${request.id}:proposal:${index}`;
      if (providerProposal.operation === 'propose-outcome') {
        await stageMemoryConfirmation(transaction, {
          confirmationId: proposalId,
          proposal: providerProposal as unknown as GovernedMemoryDelta,
          conversationId: request.conversationId,
          sourceMessageId: sourceMessage.id,
          stagedAt: effectiveAt,
          idempotencyId: `${proposalId}:stage`,
          presentation: { kind: 'proposal', question: null },
        });
        pendingProposals.push({
          id: proposalId,
          summary: providerProposal.candidate.kind === 'evidence'
            ? providerProposal.candidate.statement
            : providerProposal.candidate.title,
          kind: 'proposal', question: null, status: 'pending',
        });
        continue;
      }
      const admission = admitGatewayMemoryDelta(
        providerProposal,
        await governanceState(transaction),
        { conversationId: request.conversationId, sourceMessage },
      );
      if (admission.status === 'rejected' || admission.status === 'archive-only') continue;
      const delta = admission.status === 'clarification-required'
        ? admission.candidate
        : admission.delta;
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
          presentation: admission.status === 'clarification-required'
            ? { kind: 'clarification', question: admission.question }
            : { kind: 'proposal', question: null },
        });
        pendingProposals.push({
          id: proposalId,
          summary: delta.operation === 'propose' ? delta.candidate.statement : delta.reason,
          kind: admission.status === 'clarification-required' ? 'clarification' : 'proposal',
          question: admission.status === 'clarification-required' ? admission.question : null,
          status: 'pending',
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

  async function runCoachingOnce(requestId: string): Promise<CompletedSubmissionResult> {
    const storedRequest = await getCoachingRequest(dependencies.database, requestId);
    if (storedRequest === null) throw new LocalSubmissionStateError('Submission no longer exists');
    const storedMessage = await getMessage(dependencies.database, storedRequest.userMessageId);
    if (storedMessage === null) throw new LocalSubmissionStateError('Submission message no longer exists');
    const profileId = await dependencies.getProfileId();
    let assembled;
    try {
      const [activeGoals, openActions] = await Promise.all([
        listGoals(dependencies.database, ['active'], COACHING_GATEWAY_LIMITS.maxMemoryItems),
        listActions(dependencies.database, ['open'], COACHING_GATEWAY_LIMITS.maxMemoryItems),
      ]);
      const relatedGoalIds = activeGoals
        .map((goal) => goal.id)
        .slice(0, COACHING_GATEWAY_LIMITS.maxIdListLength);
      const relatedActionIds = openActions
        .map((action) => action.id)
        .slice(0, COACHING_GATEWAY_LIMITS.maxIdListLength);
      assembled = await assembleCoachingContext(
        {
          requestId: storedRequest.id,
          submittedAt: storedRequest.submittedAt,
          submittedThought: storedMessage.content,
          conversationId: storedRequest.conversationId,
          profileId,
          directEvidenceIds: [],
          directSourceMessageIds: [storedMessage.id],
          relatedGoalIds,
          relatedActionIds,
        },
        contextRepositories(dependencies.database, activeGoals, openActions),
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

  async function runTranscriptionOnce(requestId: string): Promise<TranscriptConfirmationResult> {
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
    let retiredAudioUri: string | null = null;
    let confirmation: TranscriptConfirmationResult;
    try {
      confirmation = await withRepositoryTransaction(dependencies.database, async (transaction) => {
        const current = await getCoachingRequest(transaction, requestId);
        const message = current === null ? null : await getMessage(transaction, current.userMessageId);
        if (
          current === null ||
          message === null ||
          current.transcriptionRequestId === null ||
          current.audioUri === null
        ) {
          throw new LocalSubmissionStateError('Voice submission state changed');
        }
        const audioUri = current.audioUri;
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
        await enqueueAudioCleanup(transaction, {
          audioUri,
          enqueuedAt: timestamp,
        });
        await updateCoachingRequest(
          transaction,
          {
            ...current,
            status: 'transcript-confirmation-required',
            audioUri: null,
            audioDurationSeconds: result.durationSeconds,
            errorCode: null,
            updatedAt: timestamp,
          },
          `${current.id}:attempt:${current.attemptCount}:transcript-complete`,
        );
        retiredAudioUri = audioUri;
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
    if (retiredAudioUri !== null) {
      // The queue and retired request pointer already committed atomically, so
      // any cleanup-processing failure remains recoverable at next startup.
      await joinRecordingCleanup(retiredAudioUri, false).catch(() => {});
    }
    return confirmation;
  }

  async function pendingProposalFromConfirmation(
    confirmation: LocalMemoryConfirmation,
  ): Promise<PendingProposal | null> {
    let delta: GovernedMemoryDelta;
    try {
      delta = JSON.parse(confirmation.proposalJson) as GovernedMemoryDelta;
    } catch {
      return null;
    }
    const outcome = delta as unknown as OutcomeDelta;
    const summary = outcome.operation === 'propose-outcome'
      ? outcome.candidate.kind === 'evidence' ? outcome.candidate.statement : outcome.candidate.title
      : delta.operation === 'propose' ? delta.candidate.statement : delta.reason;
    return {
      id: confirmation.id,
      summary,
      kind: confirmation.presentationKind,
      question: confirmation.clarificationQuestion,
      status: confirmation.status === 'confirmed' ? 'confirmed' : 'pending',
    };
  }

  function runCoaching(requestId: string): Promise<CompletedSubmissionResult> {
    return withInFlightRequest(requestId, () => runCoachingOnce(requestId));
  }

  function runTranscription(requestId: string): Promise<TranscriptConfirmationResult> {
    return withInFlightRequest(requestId, () => runTranscriptionOnce(requestId));
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

    submitText(input) {
      let content: string;
      let intentId: string;
      try {
        content = validateCoachingContent(input.content, 'Submitted thought');
        intentId = input.intentId === undefined
          ? `request-intent:${dependencies.createId()}`
          : requireContent(input.intentId, 'Submission intent ID');
      } catch (error) {
        return Promise.reject(error);
      }
      return withInFlightIntent(intentId, async () => {
        const timestamp = dependencies.now();
        const requestId = input.intentId === undefined
          ? intentId.slice('request-intent:'.length)
          : dependencies.createId();
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
              intentId,
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
      });
    },

    submitVoice(input) {
      if (!Number.isFinite(input.durationSeconds) || input.durationSeconds <= 0) {
        return Promise.reject(new TypeError('Recording duration must be a positive number'));
      }
      const sourceUri = requireContent(input.audioUri, 'Audio URI');
      const intentId = input.intentId === undefined
        ? `request-intent:${dependencies.createId()}`
        : requireContent(input.intentId, 'Submission intent ID');
      return withInFlightIntent(intentId, async () => {
        const timestamp = dependencies.now();
        const requestId = input.intentId === undefined
          ? intentId.slice('request-intent:'.length)
          : dependencies.createId();
        const messageId = dependencies.createId();
        const transcriptionRequestId = dependencies.createId();
        const durableAudioUri = await dependencies.audioFiles.persistRecording({
          sourceUri,
          requestId,
        });
        try {
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
                intentId,
                conversationId: input.conversationId,
                userMessageId: messageId,
                transcriptionRequestId,
                kind: 'voice',
                status: 'transcription-pending',
                audioUri: durableAudioUri,
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
        } catch (error) {
          await queueAndAttemptRecordingCleanup(durableAudioUri);
          throw error;
        }
        if (sourceUri !== durableAudioUri) {
          await queueAndAttemptRecordingCleanup(sourceUri);
        }
        return runTranscription(requestId);
      });
    },

    async updateTranscript(input) {
      const transcript = requireContent(input.transcript, 'Transcript');
      const timestamp = dependencies.now();
      await withRepositoryTransaction(dependencies.database, async (transaction) => {
        const request = await getCoachingRequest(transaction, input.requestId);
        if (
          request === null ||
          (request.status !== 'transcript-confirmation-required' &&
            !(request.kind === 'voice' && request.status === 'coaching-failed'))
        ) {
          throw new LocalSubmissionStateError('Transcript is not available for editing');
        }
        const message = await getMessage(transaction, request.userMessageId);
        if (message === null) throw new LocalSubmissionStateError('Transcript message is missing');
        await updateMessage(
          transaction,
          { ...message, content: transcript, updatedAt: timestamp },
          `${request.id}:transcript-edit:${dependencies.createId()}`,
        );
        if (request.status === 'coaching-failed') {
          await updateCoachingRequest(
            transaction,
            {
              ...request,
              status: 'transcript-confirmation-required',
              transcriptConfirmedAt: null,
              errorCode: null,
              attemptCount: request.attemptCount + 1,
              updatedAt: timestamp,
            },
            `${request.id}:transcript-edit-reopen:${dependencies.createId()}`,
          );
        }
      });
    },

    confirmTranscript(input) {
      return withInFlightIntent(`confirm-transcript:${input.requestId}`, async () => {
        const timestamp = dependencies.now();
        await withRepositoryTransaction(dependencies.database, async (transaction) => {
          const request = await getCoachingRequest(transaction, input.requestId);
          if (request === null || request.status !== 'transcript-confirmation-required') {
            throw new LocalSubmissionStateError('Transcript requires explicit confirmation');
          }
          const message = await getMessage(transaction, request.userMessageId);
          if (message === null) throw new LocalSubmissionStateError('Transcript message is missing');
          validateCoachingContent(message.content, 'Transcript');
          await updateCoachingRequest(
            transaction,
            {
              ...request,
              status: 'coaching-pending',
              transcriptConfirmedAt: timestamp,
              errorCode: null,
              updatedAt: timestamp,
            },
            `${request.id}:attempt:${request.attemptCount}:transcript-confirmed`,
          );
        });
        return runCoaching(input.requestId);
      });
    },

    retrySubmission(requestId) {
      const currentRequest = inFlightRequests.get(requestId);
      if (currentRequest !== undefined) return currentRequest;
      return withInFlightIntent(`retry:${requestId}`, async () => {
        const timestamp = dependencies.now();
        const request = await withRepositoryTransaction(
          dependencies.database,
          async (transaction) => {
            const current = await getCoachingRequest(transaction, requestId);
            if (
              current === null ||
              ![
                'transcription-pending',
                'transcription-failed',
                'coaching-pending',
                'coaching-failed',
              ].includes(current.status)
            ) {
              throw new LocalSubmissionStateError(
                'Only an interrupted or failed submission can be retried',
              );
            }
            const message = await getMessage(transaction, current.userMessageId);
            if (message === null) {
              throw new LocalSubmissionStateError('Submission message is missing');
            }
            const attemptCount = current.attemptCount + 1;
            const status = current.status === 'transcription-failed' ||
              current.status === 'transcription-pending'
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
      });
    },

    async hydrateConversation(conversationId) {
      let requests = await listCoachingRequestsByConversation(
        dependencies.database,
        conversationId,
        [
          'transcription-pending',
          'transcription-failed',
          'transcript-confirmation-required',
          'coaching-pending',
          'coaching-failed',
        ],
        1,
      );
      if (requests.length === 0) {
        requests = await listCoachingRequestsByConversation(
          dependencies.database,
          conversationId,
          ['completed'],
          1,
        );
      }
      const request = requests[0] ?? null;
      const message = request === null
        ? null
        : await getMessage(dependencies.database, request.userMessageId);
      const confirmations = await listMemoryConfirmationsByConversation(
        dependencies.database,
        conversationId,
        ['pending', 'confirmed'],
        20,
      );
      const pendingProposals = (
        await Promise.all(confirmations.map(pendingProposalFromConfirmation))
      ).filter((proposal): proposal is PendingProposal => proposal !== null);
      return {
        requestId: request?.id ?? null,
        messageId: request?.userMessageId ?? null,
        requestStatus: request?.status ?? null,
        transcript: request?.kind === 'voice' ? message?.content ?? '' : '',
        pendingProposals,
      };
    },

    drainAudioCleanupQueue,

    async discardRecording(uri) {
      await queueAndAttemptRecordingCleanup(requireContent(uri, 'Recording URI'));
    },

    async abandonVoiceSubmission(requestId) {
      const timestamp = dependencies.now();
      const abandoned = await withRepositoryTransaction(
        dependencies.database,
        async (transaction) => {
          const request = await getCoachingRequest(transaction, requestId);
          if (request === null || request.kind !== 'voice' || request.status === 'completed') {
            throw new LocalSubmissionStateError('Voice submission cannot be abandoned');
          }
          if (request.status === 'abandoned') return request;
          const message = await getMessage(transaction, request.userMessageId);
          if (message === null) throw new LocalSubmissionStateError('Voice message is missing');
          await updateMessage(
            transaction,
            { ...message, lifecycle: 'private', updatedAt: timestamp },
            `${request.id}:abandon-message`,
          );
          const updated: LocalCoachingRequest = {
            ...request,
            status: 'abandoned',
            errorCode: null,
            updatedAt: timestamp,
          };
          await updateCoachingRequest(
            transaction,
            updated,
            `${request.id}:abandon-request`,
          );
          return updated;
        },
      );
      if (abandoned.audioUri === null) return;
      await queueAndAttemptRecordingCleanup(abandoned.audioUri);
    },

    async confirmProposal(input) {
      requireContent(input.localUserActionId, 'Local user action ID');
      await withRepositoryTransaction(dependencies.database, async (transaction) => {
        const confirmation = await getMemoryConfirmation(transaction, input.confirmationId);
        if (confirmation === null) {
          throw new LocalSubmissionStateError('Memory proposal no longer exists');
        }
        if (confirmation.status === 'consumed') return;
        const parsed = JSON.parse(confirmation.proposalJson) as GovernedMemoryDelta | OutcomeDelta;
        if (parsed.operation === 'propose-outcome') {
          const outcomeId = `${confirmation.id}:outcome`;
          const resolution = { kind: 'apply-outcome', proposal: parsed, outcomeId, effectiveAt: input.actedAt };
          await confirmMemoryResolution(transaction, {
            confirmationId: confirmation.id, resolution,
            localUserAction: { id: input.localUserActionId, kind: 'explicit-confirm', actedAt: input.actedAt },
            idempotencyId: `${confirmation.id}:confirm`,
          });
          await consumeConfirmedMemoryResolution(transaction, {
            confirmationId: confirmation.id, resolution, consumedAt: input.actedAt,
            consumedByIdempotencyId: `${confirmation.id}:apply`,
          });
          const candidate = parsed.candidate;
          if (candidate.kind === 'goal') {
            await insertGoal(transaction, {
              id: outcomeId, title: candidate.title, description: candidate.description,
              lifecycle: 'active', priority: candidate.priority, progressPercent: 0,
              targetDate: candidate.targetDate, sourceMessageId: confirmation.sourceMessageId,
              supersedesId: candidate.supersedesId, createdAt: input.actedAt,
              updatedAt: input.actedAt, statusChangedAt: input.actedAt,
            }, `${confirmation.id}:outcome`);
          } else if (candidate.kind === 'action') {
            await insertAction(transaction, {
              id: outcomeId, goalId: candidate.goalId, sourceMessageId: confirmation.sourceMessageId,
              title: candidate.title, description: candidate.description, lifecycle: 'open',
              priority: candidate.priority, dueAt: candidate.dueAt, supersedesId: candidate.supersedesId,
              createdAt: input.actedAt, updatedAt: input.actedAt, statusChangedAt: input.actedAt,
            }, `${confirmation.id}:outcome`);
          } else {
            await insertEvidence(transaction, {
              id: outcomeId, statement: candidate.statement, occurredAt: candidate.occurredAt,
              sourceMessageIds: [confirmation.sourceMessageId], goalIds: candidate.goalIds,
              actionIds: candidate.actionIds, createdAt: input.actedAt, updatedAt: input.actedAt,
            }, `${confirmation.id}:outcome`);
          }
          return;
        }
        const delta = parsed;
        if (
          delta.operation === 'propose' &&
          (delta.changeKind === 'replace' || delta.conflictsWithIds.length > 0)
        ) {
          throw new LocalSubmissionStateError(
            'This memory clarification requires a replace, pause, or coexist choice',
          );
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

    async resolveClarification(input) {
      requireContent(input.localUserActionId, 'Local user action ID');
      if (!['replace', 'pause', 'coexist'].includes(input.choice)) {
        throw new LocalSubmissionStateError('Unknown clarification choice');
      }
      await withRepositoryTransaction(dependencies.database, async (transaction) => {
        const confirmation = await getMemoryConfirmation(transaction, input.confirmationId);
        if (confirmation === null) {
          throw new LocalSubmissionStateError('Memory clarification no longer exists');
        }
        if (confirmation.status === 'consumed') return;
        const delta = JSON.parse(confirmation.proposalJson) as GovernedMemoryDelta;
        if (
          delta.operation !== 'propose' ||
          delta.changeKind !== 'replace' ||
          delta.conflictsWithIds.length === 0
        ) {
          throw new LocalSubmissionStateError('This proposal does not require clarification');
        }
        const successorId = `${confirmation.id}:memory`;
        const predecessorIds = [...delta.conflictsWithIds];
        const linkedMemoryIds = input.choice === 'coexist'
          ? [successorId]
          : [successorId, ...predecessorIds];
        const sourceLinks = linkedMemoryIds.map((memoryId) => sourceLink(
          `${confirmation.id}:${input.choice}:source:${memoryId}`,
          memoryId,
          confirmation.sourceMessageId,
          input.actedAt,
        ));
        const application: ConfirmedClarificationResolutionApplication = {
          confirmationId: confirmation.id,
          idempotencyId: `${confirmation.id}:apply:${input.choice}`,
          effectiveAt: input.actedAt,
          successorId,
          candidate: delta,
          predecessorIds,
          choice: input.choice,
          sourceLinks,
        };
        const resolution = confirmedClarificationResolutionPayload(application);
        await confirmMemoryResolution(transaction, {
          confirmationId: confirmation.id,
          resolution,
          localUserAction: {
            id: input.localUserActionId,
            kind: 'explicit-confirm',
            actedAt: input.actedAt,
          },
          idempotencyId: `${confirmation.id}:confirm:${input.choice}`,
        });
        await applyConfirmedClarificationResolution(transaction, application);
      });
    },
  };
}

export type { ContextManifest };
export type { AudioFileStore } from './audioFileStore';
