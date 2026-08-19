import type {
  CoachingContext,
  CoachingRequest,
  LocalCareerProfile,
  LocalEvidenceItem,
  LocalMemoryItem,
  LocalMessage,
  MemoryLifecycle,
} from '@taisa/shared';
import {
  COACHING_GATEWAY_LIMITS,
  firstCoachingRequestContractViolation,
} from '@taisa/shared';

import { rankEvidence } from './rankEvidence';

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
  | 'incomplete-profile'
  | 'invalid-field'
  | 'text-truncated'
  | 'relationship-limit'
  | 'relationship-duplicate';

export interface ContextManifest {
  included: {
    profileId: string | null;
    messageIds: string[];
    memoryIds: string[];
    evidenceIds: string[];
  };
  excluded: Array<{
    entityType: 'profile' | 'message' | 'memory' | 'evidence' | 'query';
    id: string;
    reason: ContextExclusionReason;
    field?: string;
    relatedId?: string;
  }>;
  queryLimits: { messages: number; memory: number; evidence: number };
  serializedCharacters: number;
  estimatedTokens: number;
}

export interface AssembledCoachingContext {
  request: CoachingRequest;
  context: CoachingContext;
  manifest: ContextManifest;
}

export class ContextContractViolationError extends Error {
  readonly code = 'CONTEXT_CONTRACT_VIOLATION';

  constructor(readonly field: string) {
    super('A coaching request field does not satisfy the portable gateway contract');
    this.name = 'ContextContractViolationError';
  }
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

function isGatewayId(value: unknown): value is string {
  return (
    typeof value === 'string' &&
    value.length > 0 &&
    value.length <= COACHING_GATEWAY_LIMITS.maxIdLength &&
    value.trim() === value
  );
}

function isGatewayTimestamp(value: unknown): value is string {
  if (
    typeof value !== 'string' ||
    value.length > COACHING_GATEWAY_LIMITS.maxTimestampLength ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/.test(value)
  ) {
    return false;
  }
  return Number.isFinite(Date.parse(value));
}

function isGatewayRequestId(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
    value,
  );
}

function normalizedSubmittedInput(input: ContextAssemblyInput): string {
  if (!isGatewayRequestId(input.requestId)) {
    throw new ContextContractViolationError('requestId');
  }
  if (!isGatewayTimestamp(input.submittedAt)) {
    throw new ContextContractViolationError('submittedAt');
  }
  const submittedThought = input.submittedThought.trim();
  if (
    submittedThought.length === 0 ||
    submittedThought.length > COACHING_GATEWAY_LIMITS.maxTextLength
  ) {
    throw new ContextContractViolationError('submittedThought');
  }
  return submittedThought;
}

function timestampValue(value: string): number {
  if (!isGatewayTimestamp(value)) {
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
  const currentRole = profile.currentRole.trim();
  const currentCompany = profile.currentCompany?.trim() ?? null;
  const currentFocusArea = profile.currentFocusArea?.trim() ?? '';
  const shortTermGoal = profile.shortTermGoal?.trim() ?? '';
  const longTermGoal = profile.longTermGoal?.trim() ?? '';
  if (
    currentRole.length === 0 ||
    currentRole.length > COACHING_GATEWAY_LIMITS.maxProfileFieldLength
  ) {
    throw new ContextContractViolationError('profile.currentRole');
  }
  if (
    currentCompany !== null &&
    (currentCompany.length === 0 ||
      currentCompany.length > COACHING_GATEWAY_LIMITS.maxProfileFieldLength)
  ) {
    throw new ContextContractViolationError('profile.currentCompany');
  }
  for (const [field, value] of [
    ['currentFocusArea', currentFocusArea],
    ['shortTermGoal', shortTermGoal],
    ['longTermGoal', longTermGoal],
  ] as const) {
    if (value.length > COACHING_GATEWAY_LIMITS.maxProfileFieldLength) {
      throw new ContextContractViolationError(`profile.${field}`);
    }
  }
  return {
    currentRole,
    currentCompany,
    careerStage: profile.careerStage,
    currentFocusArea,
    shortTermGoal,
    longTermGoal,
    coachingStyle: profile.coachingStyle,
    accountabilityLevel: profile.accountabilityLevel,
  };
}

function compactText(
  value: string,
  entityType: 'message' | 'memory' | 'evidence',
  id: string,
  field: string,
  excluded: ContextManifest['excluded'],
  trim: boolean,
): string | null {
  const normalized = trim ? value.trim() : value;
  if (trim && normalized.length === 0) {
    excluded.push({ entityType, id, field, reason: 'invalid-field' });
    return null;
  }
  if (normalized.length <= COACHING_GATEWAY_LIMITS.maxTextLength) return normalized;
  excluded.push({ entityType, id, field, reason: 'text-truncated' });
  return normalized.slice(0, COACHING_GATEWAY_LIMITS.maxTextLength);
}

function compactIdList(
  values: readonly string[],
  entityType: 'memory' | 'evidence' | 'query',
  id: string,
  field: string,
  excluded: ContextManifest['excluded'],
): string[] {
  const valid: string[] = [];
  const seen = new Set<string>();
  for (const value of values) {
    if (!isGatewayId(value)) {
      excluded.push({
        entityType,
        id,
        field,
        reason: 'invalid-field',
      });
      continue;
    }
    if (seen.has(value)) {
      excluded.push({
        entityType,
        id,
        field,
        relatedId: value,
        reason: 'relationship-duplicate',
      });
      continue;
    }
    seen.add(value);
    valid.push(value);
  }
  valid.sort(stableCompare);
  for (const value of valid.slice(COACHING_GATEWAY_LIMITS.maxIdListLength)) {
    excluded.push({
      entityType,
      id,
      field,
      relatedId: value,
      reason: 'relationship-limit',
    });
  }
  return valid.slice(0, COACHING_GATEWAY_LIMITS.maxIdListLength);
}

function compactMemory(
  item: LocalMemoryItem,
  excluded: ContextManifest['excluded'],
): CoachingContext['memory'][number] | null {
  const statement = compactText(item.statement, 'memory', item.id, 'statement', excluded, true);
  if (statement === null) return null;
  return {
    id: item.id,
    type: item.type,
    statement,
    provenance: item.provenance,
    lifecycle: item.lifecycle,
    confidence: item.confidence,
    createdAt: item.createdAt,
    confirmedAt: item.confirmedAt,
    lastSupportedAt: item.lastSupportedAt,
    statusChangedAt: item.statusChangedAt,
    sourceMessageIds: compactIdList(
      item.sourceMessageIds,
      'memory',
      item.id,
      'sourceMessageIds',
      excluded,
    ),
    supersedesId: item.supersedesId ?? null,
  };
}

function compactEvidence(
  item: LocalEvidenceItem,
  excluded: ContextManifest['excluded'],
): CoachingContext['evidence'][number] | null {
  const statement = compactText(item.statement, 'evidence', item.id, 'statement', excluded, true);
  if (statement === null) return null;
  return {
    id: item.id,
    statement,
    occurredAt: item.occurredAt,
    sourceMessageIds: compactIdList(
      item.sourceMessageIds,
      'evidence',
      item.id,
      'sourceMessageIds',
      excluded,
    ),
    goalIds: compactIdList(item.goalIds, 'evidence', item.id, 'goalIds', excluded),
    actionIds: compactIdList(item.actionIds, 'evidence', item.id, 'actionIds', excluded),
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

function serializedStats(request: CoachingRequest): { characters: number; tokens: number } {
  const serialized = JSON.stringify(request);
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

function invalidMemoryField(item: LocalMemoryItem): string | null {
  if (!isGatewayId(item.id)) return 'id';
  if (!isGatewayTimestamp(item.createdAt)) return 'createdAt';
  if (item.confirmedAt !== null && !isGatewayTimestamp(item.confirmedAt)) return 'confirmedAt';
  if (!isGatewayTimestamp(item.lastSupportedAt)) return 'lastSupportedAt';
  if (!isGatewayTimestamp(item.statusChangedAt)) return 'statusChangedAt';
  if (item.supersedesId != null && !isGatewayId(item.supersedesId)) return 'supersedesId';
  if (
    ![
      'goal',
      'commitment',
      'decision',
      'preference',
      'career_context',
      'development_area',
      'evidence',
      'pattern',
    ].includes(item.type)
  ) return 'type';
  if (!['user-stated', 'user-confirmed', 'ai-inferred', 'system-observed'].includes(item.provenance)) {
    return 'provenance';
  }
  if (!['proposed', 'active', 'paused', 'superseded', 'completed', 'rejected', 'archived'].includes(item.lifecycle)) {
    return 'lifecycle';
  }
  if (!['tentative', 'supported', 'established'].includes(item.confidence)) return 'confidence';
  return null;
}

function invalidEvidenceField(item: LocalEvidenceItem): string | null {
  if (!isGatewayId(item.id)) return 'id';
  if (!isGatewayTimestamp(item.occurredAt)) return 'occurredAt';
  return null;
}

function validateProfileEnums(profile: CoachingContext['profile']): void {
  if (profile === null) return;
  if (!['early', 'mid', 'senior', 'executive', 'founder'].includes(profile.careerStage)) {
    throw new ContextContractViolationError('profile.careerStage');
  }
  if (!['direct', 'supportive', 'socratic', 'structured'].includes(profile.coachingStyle)) {
    throw new ContextContractViolationError('profile.coachingStyle');
  }
  if (!['gentle', 'moderate', 'intense'].includes(profile.accountabilityLevel)) {
    throw new ContextContractViolationError('profile.accountabilityLevel');
  }
}

export async function assembleCoachingContext(
  input: ContextAssemblyInput,
  repositories: ContextRepositories,
  limits: ContextAssemblyLimits,
): Promise<AssembledCoachingContext> {
  const submittedInput = normalizedSubmittedInput(input);
  positiveInteger(limits.maxCharacters, 'Character budget');
  positiveInteger(limits.maxEstimatedTokens, 'Token budget');
  const maxMessages = boundedLimit(
    limits.maxMessages ?? COACHING_GATEWAY_LIMITS.maxRecentMessages,
    COACHING_GATEWAY_LIMITS.maxRecentMessages,
    'Message limit',
  );
  const maxMemory = boundedLimit(
    limits.maxMemory ?? COACHING_GATEWAY_LIMITS.maxMemoryItems,
    COACHING_GATEWAY_LIMITS.maxMemoryItems,
    'Memory limit',
  );
  const maxEvidence = boundedLimit(
    limits.maxEvidence ?? COACHING_GATEWAY_LIMITS.maxEvidenceItems,
    COACHING_GATEWAY_LIMITS.maxEvidenceItems,
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
  const directEvidenceIds = compactIdList(
    input.directEvidenceIds,
    'query',
    input.requestId,
    'directEvidenceIds',
    excluded,
  );
  const directSourceMessageIds = compactIdList(
    input.directSourceMessageIds,
    'query',
    input.requestId,
    'directSourceMessageIds',
    excluded,
  );
  const relatedGoalIds = compactIdList(
    input.relatedGoalIds,
    'query',
    input.requestId,
    'relatedGoalIds',
    excluded,
  );
  const relatedActionIds = compactIdList(
    input.relatedActionIds,
    'query',
    input.requestId,
    'relatedActionIds',
    excluded,
  );

  const [storedProfile, returnedMessages, returnedMemory, returnedEvidence] = await Promise.all([
    repositories.getProfile(input.profileId),
    repositories.listRecentMessages(input.conversationId, maxMessages),
    repositories.listMemoryCandidates(['active', 'paused'], memoryQueryLimit),
    repositories.listEvidenceCandidates(submittedInput, evidenceQueryLimit),
  ]);

  const scopedMessages = uniqueById(returnedMessages, 'message', excluded).filter((message) => {
    if (!isGatewayId(message.id)) {
      excluded.push({ entityType: 'message', id: message.id, field: 'id', reason: 'invalid-field' });
      return false;
    }
    if (message.conversationId !== input.conversationId) {
      excluded.push({ entityType: 'message', id: message.id, reason: 'scope-mismatch' });
      return false;
    }
    if (message.lifecycle !== 'submitted' && message.lifecycle !== 'received') {
      excluded.push({ entityType: 'message', id: message.id, reason: 'not-submitted' });
      return false;
    }
    if (!isGatewayTimestamp(message.createdAt)) {
      excluded.push({
        entityType: 'message',
        id: message.id,
        field: 'createdAt',
        reason: 'invalid-field',
      });
      return false;
    }
    if (
      (message.role !== 'user' && message.role !== 'assistant') ||
      typeof message.content !== 'string'
    ) {
      excluded.push({
        entityType: 'message',
        id: message.id,
        field: message.role !== 'user' && message.role !== 'assistant' ? 'role' : 'content',
        reason: 'invalid-field',
      });
      return false;
    }
    return true;
  });
  const orderedMessages = scopedMessages.sort(
    (left, right) =>
      timestampValue(left.createdAt) - timestampValue(right.createdAt) ||
      stableCompare(left.id, right.id),
  );
  const selectedMessages = orderedMessages.slice(-maxMessages).map((message) => ({
    ...message,
    content: compactText(message.content, 'message', message.id, 'content', excluded, false)!,
  }));
  for (const item of orderedMessages.slice(0, Math.max(0, orderedMessages.length - maxMessages))) {
    excluded.push({ entityType: 'message', id: item.id, reason: 'count-limit' });
  }

  const liveMemory = uniqueById(returnedMemory, 'memory', excluded).filter((item) => {
    const invalidField = invalidMemoryField(item);
    if (invalidField !== null) {
      excluded.push({
        entityType: 'memory',
        id: item.id,
        field: invalidField,
        reason: 'invalid-field',
      });
      return false;
    }
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
  const selectedMemory = liveMemory
    .slice(0, maxMemory)
    .map((item) => compactMemory(item, excluded))
    .filter((item): item is CoachingContext['memory'][number] => item !== null);
  for (const item of liveMemory.slice(maxMemory)) {
    excluded.push({ entityType: 'memory', id: item.id, reason: 'count-limit' });
  }

  const uniqueEvidence = uniqueById(returnedEvidence, 'evidence', excluded)
    .filter((item) => {
      const invalidField = invalidEvidenceField(item);
      if (invalidField === null) return true;
      excluded.push({
        entityType: 'evidence',
        id: item.id,
        field: invalidField,
        reason: 'invalid-field',
      });
      return false;
    })
    .map((item) => compactEvidence(item, excluded))
    .filter((item): item is CoachingContext['evidence'][number] => item !== null);
  const rankedEvidence = rankEvidence(
    {
      text: submittedInput,
      directEvidenceIds,
      directSourceMessageIds,
      goalIds: relatedGoalIds,
      actionIds: relatedActionIds,
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

  let profile: CoachingContext['profile'] = null;
  if (storedProfile !== null && storedProfile.id !== input.profileId) {
    excluded.push({ entityType: 'profile', id: storedProfile.id, reason: 'scope-mismatch' });
  } else if (storedProfile !== null) {
    profile = compactProfile(storedProfile);
    if (profile === null) {
      excluded.push({ entityType: 'profile', id: storedProfile.id, reason: 'incomplete-profile' });
    }
  }
  validateProfileEnums(profile);
  const messages = [...selectedMessages];
  const memory = [...selectedMemory];
  const evidence = [...selectedEvidence];
  const buildContext = (): CoachingContext => ({
    profile,
    recentMessages: messages.map((message) => ({ role: message.role, content: message.content })),
    memory: memory.map((item) => ({ ...item, sourceMessageIds: [...item.sourceMessageIds] })),
    evidence: evidence.map((item) => ({
      ...item,
      sourceMessageIds: [...item.sourceMessageIds],
      goalIds: [...item.goalIds],
      actionIds: [...item.actionIds],
    })),
  });
  const buildRequest = (context: CoachingContext): CoachingRequest => ({
    requestId: input.requestId,
    submittedAt: input.submittedAt,
    input: submittedInput,
    context,
  });

  let context = buildContext();
  let request = buildRequest(context);
  let stats = serializedStats(request);
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
    request = buildRequest(context);
    stats = serializedStats(request);
    reason = budgetReason(stats, limits);
  }
  const contractViolation = firstCoachingRequestContractViolation(request);
  if (contractViolation !== null) {
    throw new ContextContractViolationError(contractViolation);
  }

  return {
    request,
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
