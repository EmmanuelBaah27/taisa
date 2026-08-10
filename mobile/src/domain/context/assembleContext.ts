import type {
  CoachingContext,
  LocalCareerProfile,
  LocalEvidenceItem,
  LocalMemoryItem,
  LocalMessage,
  MemoryLifecycle,
} from '@taisa/shared';

import { rankEvidence } from './rankEvidence';

const HARD_MAX_MESSAGES = 20;
const HARD_MAX_MEMORY = 50;
const HARD_MAX_EVIDENCE = 8;
const HARD_MAX_CANDIDATES = 200;

export interface ContextAssemblyInput {
  requestId: string;
  submittedAt: string;
  submittedThought: string;
  conversationId: string;
  profileId: string;
  directEvidenceIds: readonly string[];
  directSourceMessageIds: readonly string[];
  relatedGoalIds: readonly string[];
  relatedActionIds: readonly string[];
}

export interface ContextRepositories {
  getProfile(profileId: string): Promise<LocalCareerProfile | null>;
  listRecentMessages(conversationId: string, limit: number): Promise<readonly LocalMessage[]>;
  listMemoryCandidates(
    lifecycles: readonly MemoryLifecycle[],
    limit: number,
  ): Promise<readonly LocalMemoryItem[]>;
  listEvidenceCandidates(query: string, limit: number): Promise<readonly LocalEvidenceItem[]>;
}

export interface ContextAssemblyLimits {
  maxCharacters: number;
  maxEstimatedTokens: number;
  memoryCandidateLimit: number;
  evidenceCandidateLimit: number;
  maxMessages?: number;
  maxMemory?: number;
  maxEvidence?: number;
}

export type ContextExclusionReason =
  | 'count-limit'
  | 'character-budget'
  | 'token-budget'
  | 'character-and-token-budget'
  | 'not-relevant'
  | 'lifecycle-filtered'
  | 'scope-mismatch'
  | 'not-submitted'
  | 'duplicate-id'
  | 'incomplete-profile';

export interface ContextManifest {
  included: {
    profileId: string | null;
    messageIds: string[];
    memoryIds: string[];
    evidenceIds: string[];
  };
  excluded: Array<{
    entityType: 'profile' | 'message' | 'memory' | 'evidence';
    id: string;
    reason: ContextExclusionReason;
  }>;
  queryLimits: { messages: number; memory: number; evidence: number };
  serializedCharacters: number;
  estimatedTokens: number;
}

export interface AssembledCoachingContext {
  context: CoachingContext;
  manifest: ContextManifest;
}

export class ContextBudgetExceededError extends Error {
  readonly code = 'CONTEXT_BUDGET_EXCEEDED';

  constructor(
    readonly serializedCharacters: number,
    readonly estimatedTokens: number,
  ) {
    super('Submitted turn exceeds the configured context budget');
    this.name = 'ContextBudgetExceededError';
  }
}

function positiveInteger(value: number, label: string): number {
  if (!Number.isInteger(value) || value <= 0) {
    throw new TypeError(`${label} must be a positive integer`);
  }
  return value;
}

function boundedLimit(value: number, maximum: number, label: string): number {
  return Math.min(positiveInteger(value, label), maximum);
}

function stableCompare(left: string, right: string): number {
  if (left < right) return -1;
  if (left > right) return 1;
  return 0;
}

function timestampValue(value: string): number {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?(?:Z|[+-]\d{2}:\d{2})$/.test(value)) {
    return Number.NEGATIVE_INFINITY;
  }
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : Number.NEGATIVE_INFINITY;
}

function uniqueById<T extends { id: string }>(
  items: readonly T[],
  entityType: 'message' | 'memory' | 'evidence',
  excluded: ContextManifest['excluded'],
): T[] {
  const seen = new Set<string>();
  const unique: T[] = [];
  for (const item of items) {
    if (seen.has(item.id)) {
      excluded.push({ entityType, id: item.id, reason: 'duplicate-id' });
    } else {
      seen.add(item.id);
      unique.push(item);
    }
  }
  return unique;
}

function compactProfile(profile: LocalCareerProfile | null): CoachingContext['profile'] {
  if (
    profile === null ||
    profile.currentRole === null ||
    profile.careerStage === null ||
    profile.coachingStyle === null ||
    profile.accountabilityLevel === null
  ) {
    return null;
  }
  return {
    currentRole: profile.currentRole,
    currentCompany: profile.currentCompany,
    careerStage: profile.careerStage,
    coachingStyle: profile.coachingStyle,
    accountabilityLevel: profile.accountabilityLevel,
  };
}

function compactMemory(item: LocalMemoryItem): CoachingContext['memory'][number] {
  return {
    id: item.id,
    type: item.type,
    statement: item.statement,
    provenance: item.provenance,
    lifecycle: item.lifecycle,
    confidence: item.confidence,
    createdAt: item.createdAt,
    confirmedAt: item.confirmedAt,
    lastSupportedAt: item.lastSupportedAt,
    statusChangedAt: item.statusChangedAt,
    sourceMessageIds: [...item.sourceMessageIds],
    supersedesId: item.supersedesId ?? null,
  };
}

function compactEvidence(item: LocalEvidenceItem): CoachingContext['evidence'][number] {
  return {
    id: item.id,
    statement: item.statement,
    occurredAt: item.occurredAt,
    sourceMessageIds: [...item.sourceMessageIds],
    goalIds: [...item.goalIds],
    actionIds: [...item.actionIds],
  };
}

function utf8ByteLength(value: string): number {
  let bytes = 0;
  for (const character of value) {
    const codePoint = character.codePointAt(0)!;
    if (codePoint <= 0x7f) bytes += 1;
    else if (codePoint <= 0x7ff) bytes += 2;
    else if (codePoint <= 0xffff) bytes += 3;
    else bytes += 4;
  }
  return bytes;
}

function serializedStats(
  input: ContextAssemblyInput,
  context: CoachingContext,
): { characters: number; tokens: number } {
  const serialized = JSON.stringify({
    requestId: input.requestId,
    submittedAt: input.submittedAt,
    input: input.submittedThought,
    context,
  });
  return {
    characters: serialized.length,
    tokens: utf8ByteLength(serialized),
  };
}

function budgetReason(
  stats: { characters: number; tokens: number },
  limits: ContextAssemblyLimits,
): ContextExclusionReason | null {
  const charactersExceeded = stats.characters > limits.maxCharacters;
  const tokensExceeded = stats.tokens > limits.maxEstimatedTokens;
  if (charactersExceeded && tokensExceeded) return 'character-and-token-budget';
  if (charactersExceeded) return 'character-budget';
  if (tokensExceeded) return 'token-budget';
  return null;
}

export async function assembleCoachingContext(
  input: ContextAssemblyInput,
  repositories: ContextRepositories,
  limits: ContextAssemblyLimits,
): Promise<AssembledCoachingContext> {
  positiveInteger(limits.maxCharacters, 'Character budget');
  positiveInteger(limits.maxEstimatedTokens, 'Token budget');
  const maxMessages = boundedLimit(
    limits.maxMessages ?? HARD_MAX_MESSAGES,
    HARD_MAX_MESSAGES,
    'Message limit',
  );
  const maxMemory = boundedLimit(
    limits.maxMemory ?? HARD_MAX_MEMORY,
    HARD_MAX_MEMORY,
    'Memory limit',
  );
  const maxEvidence = boundedLimit(
    limits.maxEvidence ?? HARD_MAX_EVIDENCE,
    HARD_MAX_EVIDENCE,
    'Evidence limit',
  );
  const memoryQueryLimit = boundedLimit(
    limits.memoryCandidateLimit,
    HARD_MAX_CANDIDATES,
    'Memory candidate limit',
  );
  const evidenceQueryLimit = boundedLimit(
    limits.evidenceCandidateLimit,
    HARD_MAX_CANDIDATES,
    'Evidence candidate limit',
  );
  const excluded: ContextManifest['excluded'] = [];

  const [storedProfile, returnedMessages, returnedMemory, returnedEvidence] = await Promise.all([
    repositories.getProfile(input.profileId),
    repositories.listRecentMessages(input.conversationId, maxMessages),
    repositories.listMemoryCandidates(['active', 'paused'], memoryQueryLimit),
    repositories.listEvidenceCandidates(input.submittedThought, evidenceQueryLimit),
  ]);

  const scopedMessages = uniqueById(returnedMessages, 'message', excluded).filter((message) => {
    if (message.conversationId !== input.conversationId) {
      excluded.push({ entityType: 'message', id: message.id, reason: 'scope-mismatch' });
      return false;
    }
    if (message.lifecycle !== 'submitted' && message.lifecycle !== 'received') {
      excluded.push({ entityType: 'message', id: message.id, reason: 'not-submitted' });
      return false;
    }
    return true;
  });
  const orderedMessages = scopedMessages.sort(
    (left, right) =>
      timestampValue(left.createdAt) - timestampValue(right.createdAt) ||
      stableCompare(left.id, right.id),
  );
  const selectedMessages = orderedMessages.slice(-maxMessages);
  for (const item of orderedMessages.slice(0, Math.max(0, orderedMessages.length - maxMessages))) {
    excluded.push({ entityType: 'message', id: item.id, reason: 'count-limit' });
  }

  const liveMemory = uniqueById(returnedMemory, 'memory', excluded).filter((item) => {
    if (item.lifecycle !== 'active' && item.lifecycle !== 'paused') {
      excluded.push({ entityType: 'memory', id: item.id, reason: 'lifecycle-filtered' });
      return false;
    }
    return true;
  });
  liveMemory.sort(
    (left, right) =>
      Number(left.lifecycle === 'paused') - Number(right.lifecycle === 'paused') ||
      timestampValue(right.lastSupportedAt) - timestampValue(left.lastSupportedAt) ||
      stableCompare(left.id, right.id),
  );
  const selectedMemory = liveMemory.slice(0, maxMemory);
  for (const item of liveMemory.slice(maxMemory)) {
    excluded.push({ entityType: 'memory', id: item.id, reason: 'count-limit' });
  }

  const uniqueEvidence = uniqueById(returnedEvidence, 'evidence', excluded);
  const rankedEvidence = rankEvidence(
    {
      text: input.submittedThought,
      directEvidenceIds: input.directEvidenceIds,
      directSourceMessageIds: input.directSourceMessageIds,
      goalIds: input.relatedGoalIds,
      actionIds: input.relatedActionIds,
    },
    uniqueEvidence,
  );
  const rankedEvidenceIds = new Set(rankedEvidence.map((item) => item.id));
  for (const item of uniqueEvidence) {
    if (!rankedEvidenceIds.has(item.id)) {
      excluded.push({ entityType: 'evidence', id: item.id, reason: 'not-relevant' });
    }
  }
  const selectedEvidence = rankedEvidence.slice(0, maxEvidence);
  for (const item of rankedEvidence.slice(maxEvidence)) {
    excluded.push({ entityType: 'evidence', id: item.id, reason: 'count-limit' });
  }

  let profile = compactProfile(storedProfile);
  if (storedProfile !== null && storedProfile.id !== input.profileId) {
    profile = null;
    excluded.push({ entityType: 'profile', id: storedProfile.id, reason: 'scope-mismatch' });
  } else if (storedProfile !== null && profile === null) {
    excluded.push({ entityType: 'profile', id: storedProfile.id, reason: 'incomplete-profile' });
  }
  const messages = [...selectedMessages];
  const memory = [...selectedMemory];
  const evidence = [...selectedEvidence];
  const buildContext = (): CoachingContext => ({
    profile,
    recentMessages: messages.map((message) => ({ role: message.role, content: message.content })),
    memory: memory.map(compactMemory),
    evidence: evidence.map(compactEvidence),
  });

  let context = buildContext();
  let stats = serializedStats(input, context);
  let reason = budgetReason(stats, limits);
  while (reason !== null) {
    if (evidence.length > 0) {
      const removed = evidence.pop()!;
      excluded.push({ entityType: 'evidence', id: removed.id, reason });
    } else if (memory.length > 0) {
      const removed = memory.pop()!;
      excluded.push({ entityType: 'memory', id: removed.id, reason });
    } else if (messages.length > 0) {
      const removed = messages.shift()!;
      excluded.push({ entityType: 'message', id: removed.id, reason });
    } else if (profile !== null && storedProfile !== null) {
      profile = null;
      excluded.push({ entityType: 'profile', id: storedProfile.id, reason });
    } else {
      throw new ContextBudgetExceededError(stats.characters, stats.tokens);
    }
    context = buildContext();
    stats = serializedStats(input, context);
    reason = budgetReason(stats, limits);
  }

  return {
    context,
    manifest: {
      included: {
        profileId: profile === null ? null : storedProfile!.id,
        messageIds: messages.map((item) => item.id),
        memoryIds: memory.map((item) => item.id),
        evidenceIds: evidence.map((item) => item.id),
      },
      excluded,
      queryLimits: {
        messages: maxMessages,
        memory: memoryQueryLimit,
        evidence: evidenceQueryLimit,
      },
      serializedCharacters: stats.characters,
      estimatedTokens: stats.tokens,
    },
  };
}
