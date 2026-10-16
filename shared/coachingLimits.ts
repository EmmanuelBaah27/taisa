/**
 * Portable limits for requests and responses crossing the stateless coaching gateway.
 * Mobile and backend runtime validation must share these exact values.
 */
export const COACHING_GATEWAY_LIMITS = Object.freeze({
  maxIdLength: 128,
  maxTimestampLength: 40,
  maxTextLength: 4_000,
  maxProfileFieldLength: 200,
  maxIdListLength: 50,
  maxRecentMessages: 20,
  maxMemoryItems: 50,
  maxEvidenceItems: 8,
  maxProposals: 1,
  maxTitleSuggestionLength: 80,
} as const);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function hasOnlyKeys(value: Record<string, unknown>, keys: readonly string[]): boolean {
  const allowed = new Set(keys);
  return Object.keys(value).every((key) => allowed.has(key));
}

function isId(value: unknown): value is string {
  return (
    typeof value === 'string' &&
    value.trim().length > 0 &&
    value.length <= COACHING_GATEWAY_LIMITS.maxIdLength
  );
}

function isUuid(value: unknown): value is string {
  return (
    typeof value === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
  );
}

function isTimestamp(value: unknown): value is string {
  return (
    typeof value === 'string' &&
    value.length <= COACHING_GATEWAY_LIMITS.maxTimestampLength &&
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/.test(value) &&
    Number.isFinite(Date.parse(value))
  );
}

function isStatement(value: unknown): value is string {
  return (
    typeof value === 'string' &&
    value.trim().length > 0 &&
    value.trim().length <= COACHING_GATEWAY_LIMITS.maxTextLength
  );
}

function isIdList(value: unknown): value is string[] {
  return (
    Array.isArray(value) &&
    value.length <= COACHING_GATEWAY_LIMITS.maxIdListLength &&
    value.every(isId)
  );
}

function isOneOf(value: unknown, options: readonly string[]): value is string {
  return typeof value === 'string' && options.includes(value);
}

function profileViolation(value: unknown): string | null {
  if (value === null) return null;
  if (
    !isRecord(value) ||
    !hasOnlyKeys(value, [
      'currentRole',
      'currentCompany',
      'careerStage',
      'coachingStyle',
      'accountabilityLevel',
      'currentFocusArea',
      'shortTermGoal',
      'longTermGoal',
    ])
  ) return 'context.profile';
  if (
    typeof value.currentRole !== 'string' ||
    value.currentRole.trim().length === 0 ||
    value.currentRole.trim().length > COACHING_GATEWAY_LIMITS.maxProfileFieldLength
  ) return 'context.profile.currentRole';
  if (
    value.currentCompany !== null &&
    (typeof value.currentCompany !== 'string' ||
      value.currentCompany.trim().length === 0 ||
      value.currentCompany.trim().length > COACHING_GATEWAY_LIMITS.maxProfileFieldLength)
  ) return 'context.profile.currentCompany';
  if (!isOneOf(value.careerStage, ['early', 'mid', 'senior', 'executive', 'founder'])) {
    return 'context.profile.careerStage';
  }
  if (!isOneOf(value.coachingStyle, ['direct', 'supportive', 'socratic', 'structured'])) {
    return 'context.profile.coachingStyle';
  }
  if (!isOneOf(value.accountabilityLevel, ['gentle', 'moderate', 'intense'])) {
    return 'context.profile.accountabilityLevel';
  }
  for (const field of ['currentFocusArea', 'shortTermGoal', 'longTermGoal'] as const) {
    if (typeof value[field] !== 'string' || value[field].trim().length > COACHING_GATEWAY_LIMITS.maxProfileFieldLength) {
      return `context.profile.${field}`;
    }
  }
  return null;
}

function memoryViolation(value: unknown, index: number): string | null {
  const root = `context.memory[${index}]`;
  if (
    !isRecord(value) ||
    !hasOnlyKeys(value, [
      'id',
      'type',
      'statement',
      'provenance',
      'lifecycle',
      'confidence',
      'createdAt',
      'confirmedAt',
      'lastSupportedAt',
      'statusChangedAt',
      'sourceMessageIds',
      'supersedesId',
    ])
  ) return root;
  if (!isId(value.id)) return `${root}.id`;
  if (!isOneOf(value.type, ['goal', 'commitment', 'decision', 'preference', 'career_context', 'development_area', 'evidence', 'pattern'])) return `${root}.type`;
  if (!isStatement(value.statement)) return `${root}.statement`;
  if (!isOneOf(value.provenance, ['user-stated', 'user-confirmed', 'ai-inferred', 'system-observed'])) return `${root}.provenance`;
  if (!isOneOf(value.lifecycle, ['proposed', 'active', 'paused', 'superseded', 'completed', 'rejected', 'archived'])) return `${root}.lifecycle`;
  if (!isOneOf(value.confidence, ['tentative', 'supported', 'established'])) return `${root}.confidence`;
  if (!isTimestamp(value.createdAt)) return `${root}.createdAt`;
  if (value.confirmedAt !== null && !isTimestamp(value.confirmedAt)) return `${root}.confirmedAt`;
  if (!isTimestamp(value.lastSupportedAt)) return `${root}.lastSupportedAt`;
  if (!isTimestamp(value.statusChangedAt)) return `${root}.statusChangedAt`;
  if (!isIdList(value.sourceMessageIds)) return `${root}.sourceMessageIds`;
  if (value.supersedesId != null && !isId(value.supersedesId)) return `${root}.supersedesId`;
  return null;
}

function evidenceViolation(value: unknown, index: number): string | null {
  const root = `context.evidence[${index}]`;
  if (
    !isRecord(value) ||
    !hasOnlyKeys(value, [
      'id',
      'statement',
      'occurredAt',
      'sourceMessageIds',
      'goalIds',
      'actionIds',
    ])
  ) return root;
  if (!isId(value.id)) return `${root}.id`;
  if (!isStatement(value.statement)) return `${root}.statement`;
  if (!isTimestamp(value.occurredAt)) return `${root}.occurredAt`;
  if (!isIdList(value.sourceMessageIds)) return `${root}.sourceMessageIds`;
  if (!isIdList(value.goalIds)) return `${root}.goalIds`;
  if (!isIdList(value.actionIds)) return `${root}.actionIds`;
  return null;
}

/** Returns a content-free field path for the first portable gateway violation. */
export function firstCoachingRequestContractViolation(request: unknown): string | null {
  if (
    !isRecord(request) ||
    !hasOnlyKeys(request, ['requestId', 'submittedAt', 'input', 'context'])
  ) return 'request';
  if (
    !isUuid(request.requestId)
  ) return 'requestId';
  if (!isTimestamp(request.submittedAt)) return 'submittedAt';
  if (!isStatement(request.input)) return 'input';
  if (
    !isRecord(request.context) ||
    !hasOnlyKeys(request.context, ['profile', 'recentMessages', 'memory', 'evidence', 'preferenceProfile'])
  ) return 'context';
  const invalidProfile = profileViolation(request.context.profile);
  if (invalidProfile !== null) return invalidProfile;
  if (
    !Array.isArray(request.context.recentMessages) ||
    request.context.recentMessages.length > COACHING_GATEWAY_LIMITS.maxRecentMessages
  ) return 'context.recentMessages';
  for (let index = 0; index < request.context.recentMessages.length; index += 1) {
    const message = request.context.recentMessages[index];
    if (
      !isRecord(message) ||
      !hasOnlyKeys(message, ['role', 'content']) ||
      !isOneOf(message.role, ['user', 'assistant']) ||
      typeof message.content !== 'string' ||
      message.content.length > COACHING_GATEWAY_LIMITS.maxTextLength
    ) return `context.recentMessages[${index}]`;
  }
  if (
    !Array.isArray(request.context.memory) ||
    request.context.memory.length > COACHING_GATEWAY_LIMITS.maxMemoryItems
  ) return 'context.memory';
  for (let index = 0; index < request.context.memory.length; index += 1) {
    const invalidMemory = memoryViolation(request.context.memory[index], index);
    if (invalidMemory !== null) return invalidMemory;
  }
  if (
    !Array.isArray(request.context.evidence) ||
    request.context.evidence.length > COACHING_GATEWAY_LIMITS.maxEvidenceItems
  ) return 'context.evidence';
  for (let index = 0; index < request.context.evidence.length; index += 1) {
    const invalidEvidence = evidenceViolation(request.context.evidence[index], index);
    if (invalidEvidence !== null) return invalidEvidence;
  }
  if (request.context.preferenceProfile !== undefined) {
    const profile = request.context.preferenceProfile;
    if (!isRecord(profile) || !hasOnlyKeys(profile, ['signals']) || !Array.isArray(profile.signals) || profile.signals.length > 5) {
      return 'context.preferenceProfile';
    }
    for (let index = 0; index < profile.signals.length; index += 1) {
      const signal = profile.signals[index];
      if (!isRecord(signal) || !hasOnlyKeys(signal, ['factor', 'direction']) ||
          !isOneOf(signal.factor, ['intent_alignment', 'coverage', 'coaching_strategy', 'insight_value', 'practical_utility', 'confidence_calibration', 'relational_fit', 'communication_clarity']) ||
          !isOneOf(signal.direction, ['helpful', 'not_helpful'])) return `context.preferenceProfile.signals[${index}]`;
    }
  }
  return null;
}

function memoryCandidateViolation(value: unknown, root: string): string | null {
  if (
    !isRecord(value) ||
    !hasOnlyKeys(value, [
      'type',
      'statement',
      'provenance',
      'lifecycle',
      'confidence',
      'sourceMessageIds',
      'supersedesId',
    ])
  ) return root;
  if (!isOneOf(value.type, ['goal', 'commitment', 'decision', 'preference', 'career_context', 'development_area', 'evidence', 'pattern'])) return `${root}.type`;
  if (!isStatement(value.statement)) return `${root}.statement`;
  if (!isOneOf(value.provenance, ['user-stated', 'user-confirmed', 'ai-inferred', 'system-observed'])) return `${root}.provenance`;
  if (!isOneOf(value.lifecycle, ['proposed', 'active', 'paused', 'superseded', 'completed', 'rejected', 'archived'])) return `${root}.lifecycle`;
  if (!isOneOf(value.confidence, ['tentative', 'supported', 'established'])) return `${root}.confidence`;
  if (!isIdList(value.sourceMessageIds)) return `${root}.sourceMessageIds`;
  if (value.supersedesId != null && !isId(value.supersedesId)) return `${root}.supersedesId`;
  return null;
}

function memoryDeltaViolation(value: unknown, index: number): string | null {
  const root = `proposals[${index}]`;
  if (!isRecord(value)) return root;

  if (value.operation === 'propose-outcome') {
    if (!hasOnlyKeys(value, ['operation', 'candidate', 'reason', 'requiresConfirmation']) ||
      !isRecord(value.candidate) || value.requiresConfirmation !== true || !isStatement(value.reason)) return root;
    const candidate = value.candidate;
    if (candidate.kind === 'goal') {
      if (!hasOnlyKeys(candidate, ['kind', 'title', 'description', 'priority', 'targetDate', 'supersedesId']) ||
        !isStatement(candidate.title) || (candidate.description !== null && !isStatement(candidate.description)) ||
        (candidate.priority !== null && !isOneOf(candidate.priority, ['low', 'medium', 'high'])) ||
        (candidate.targetDate !== null && !isTimestamp(candidate.targetDate)) ||
        (candidate.supersedesId !== null && !isId(candidate.supersedesId))) return `${root}.candidate`;
      return null;
    }
    if (candidate.kind === 'action') {
      if (!hasOnlyKeys(candidate, ['kind', 'title', 'description', 'priority', 'dueAt', 'goalId', 'supersedesId']) ||
        !isStatement(candidate.title) || (candidate.description !== null && !isStatement(candidate.description)) ||
        (candidate.priority !== null && !isOneOf(candidate.priority, ['low', 'medium', 'high'])) ||
        (candidate.dueAt !== null && !isTimestamp(candidate.dueAt)) ||
        (candidate.goalId !== null && !isId(candidate.goalId)) ||
        (candidate.supersedesId !== null && !isId(candidate.supersedesId))) return `${root}.candidate`;
      return null;
    }
    if (candidate.kind === 'evidence') {
      if (!hasOnlyKeys(candidate, ['kind', 'statement', 'occurredAt', 'goalIds', 'actionIds']) ||
        !isStatement(candidate.statement) || !isTimestamp(candidate.occurredAt) ||
        !isIdList(candidate.goalIds) || !isIdList(candidate.actionIds)) return `${root}.candidate`;
      return null;
    }
    return `${root}.candidate.kind`;
  }

  if (value.operation === 'propose') {
    if (!hasOnlyKeys(value, ['operation', 'candidate', 'reason', 'requiresConfirmation'])) {
      return root;
    }
    const candidateViolation = memoryCandidateViolation(value.candidate, `${root}.candidate`);
    if (candidateViolation !== null) return candidateViolation;
    if (!isStatement(value.reason)) return `${root}.reason`;
    if (typeof value.requiresConfirmation !== 'boolean') return `${root}.requiresConfirmation`;
    return null;
  }

  if (value.operation === 'transition') {
    if (!hasOnlyKeys(value, ['operation', 'targetId', 'to', 'reason', 'requiresConfirmation'])) {
      return root;
    }
    if (!isId(value.targetId)) return `${root}.targetId`;
    if (!isOneOf(value.to, ['proposed', 'active', 'paused', 'superseded', 'completed', 'rejected', 'archived'])) return `${root}.to`;
    if (!isStatement(value.reason)) return `${root}.reason`;
    if (typeof value.requiresConfirmation !== 'boolean') return `${root}.requiresConfirmation`;
    return null;
  }

  if (value.operation === 'support') {
    if (!hasOnlyKeys(value, ['operation', 'targetId', 'sourceMessageId', 'reason', 'requiresConfirmation'])) {
      return root;
    }
    if (!isId(value.targetId)) return `${root}.targetId`;
    if (!isId(value.sourceMessageId)) return `${root}.sourceMessageId`;
    if (!isStatement(value.reason)) return `${root}.reason`;
    if (value.requiresConfirmation !== false) return `${root}.requiresConfirmation`;
    return null;
  }

  return `${root}.operation`;
}

function isNonNegativeFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0;
}

function explanationViolation(value: unknown, expectedMode: string | null): string | null {
  if (!isRecord(value) || !hasOnlyKeys(value, ['mode', 'evidence', 'inference', 'confidence', 'approach'])) {
    return 'explanation';
  }
  if (value.mode !== expectedMode) return 'explanation.mode';
  if (!Array.isArray(value.evidence) || value.evidence.length > COACHING_GATEWAY_LIMITS.maxEvidenceItems) {
    return 'explanation.evidence';
  }
  for (let index = 0; index < value.evidence.length; index += 1) {
    const source = value.evidence[index];
    if (!isRecord(source) || !hasOnlyKeys(source, ['sourceId', 'sourceType', 'excerpt']) ||
        !isId(source.sourceId) ||
        !isOneOf(source.sourceType, ['message', 'goal', 'action', 'evidence', 'memory', 'insight']) ||
        (source.excerpt !== null && !isStatement(source.excerpt))) {
      return `explanation.evidence[${index}]`;
    }
  }
  if (!isStatement(value.inference)) return 'explanation.inference';
  if (!isOneOf(value.confidence, ['low', 'medium', 'high'])) return 'explanation.confidence';
  if (!isStatement(value.approach)) return 'explanation.approach';
  return null;
}

function coachingProposalViolation(value: unknown): string | null {
  if (!isRecord(value) || !isOneOf(value.kind, ['goal', 'action', 'weekly_work', 'evidence', 'memory', 'insight'])) {
    return 'proposal';
  }
  if (value.kind === 'goal') {
    return hasOnlyKeys(value, ['kind', 'title', 'description', 'priority', 'targetDate']) &&
      isStatement(value.title) && (value.description === null || isStatement(value.description)) &&
      (value.priority === null || isOneOf(value.priority, ['low', 'medium', 'high'])) &&
      (value.targetDate === null || isTimestamp(value.targetDate)) ? null : 'proposal';
  }
  if (value.kind === 'action') {
    return hasOnlyKeys(value, ['kind', 'title', 'description', 'priority', 'dueAt', 'goalId']) &&
      isStatement(value.title) && (value.description === null || isStatement(value.description)) &&
      (value.priority === null || isOneOf(value.priority, ['low', 'medium', 'high'])) &&
      (value.dueAt === null || isTimestamp(value.dueAt)) && (value.goalId === null || isId(value.goalId)) ? null : 'proposal';
  }
  if (value.kind === 'weekly_work') {
    return hasOnlyKeys(value, ['kind', 'actionId', 'weekStart', 'plannedDay']) && isId(value.actionId) &&
      isTimestamp(value.weekStart) && (value.plannedDay === null || isTimestamp(value.plannedDay)) ? null : 'proposal';
  }
  if (value.kind === 'evidence') {
    return hasOnlyKeys(value, ['kind', 'statement', 'occurredAt', 'goalId', 'actionId']) &&
      isStatement(value.statement) && isTimestamp(value.occurredAt) &&
      (value.goalId === null || isId(value.goalId)) && (value.actionId === null || isId(value.actionId)) ? null : 'proposal';
  }
  if (value.kind === 'memory') {
    return hasOnlyKeys(value, ['kind', 'memory']) && memoryDeltaViolation(value.memory, 0) === null ? null : 'proposal';
  }
  return hasOnlyKeys(value, ['kind', 'body', 'isTimeSensitive', 'homeEligibleUntil']) &&
    isStatement(value.body) && typeof value.isTimeSensitive === 'boolean' &&
    (value.homeEligibleUntil === null || isTimestamp(value.homeEligibleUntil)) ? null : 'proposal';
}

function isNonNegativeSafeInteger(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;
}

function usageViolation(value: unknown): string | null {
  if (
    !isRecord(value) ||
    !hasOnlyKeys(value, [
      'provider',
      'model',
      'inputTokens',
      'outputTokens',
      'audioSeconds',
      'estimatedCostUsd',
    ])
  ) return 'usage';
  if (!isOneOf(value.provider, ['anthropic', 'openai'])) return 'usage.provider';
  if (!isId(value.model)) return 'usage.model';
  if (value.inputTokens !== undefined && !isNonNegativeSafeInteger(value.inputTokens)) {
    return 'usage.inputTokens';
  }
  if (value.outputTokens !== undefined && !isNonNegativeSafeInteger(value.outputTokens)) {
    return 'usage.outputTokens';
  }
  if (value.audioSeconds !== undefined && !isNonNegativeFiniteNumber(value.audioSeconds)) {
    return 'usage.audioSeconds';
  }
  if (!isNonNegativeFiniteNumber(value.estimatedCostUsd)) return 'usage.estimatedCostUsd';
  return null;
}

/** Returns a content-free field path for the first strict portable response violation. */
export function firstCoachingResponseContractViolation(
  response: unknown,
  expectedRequestId?: string,
): string | null {
  if (
    !isRecord(response) ||
    !hasOnlyKeys(response, [
      'requestId',
      'mode',
      'relevance',
      'contextSufficiency',
      'reply',
      'stance',
      'explanation',
      'proposal',
      'usage',
      'titleSuggestion',
    ])
  ) return 'response';
  if (!isUuid(response.requestId) || (
    expectedRequestId !== undefined && response.requestId !== expectedRequestId
  )) return 'requestId';
  if (!isOneOf(response.mode, ['coach', 'clarify', 'redirect'])) return 'mode';
  if (!isOneOf(response.relevance, ['career-relevant', 'adjacent', 'outside-scope'])) return 'relevance';
  if (!isOneOf(response.contextSufficiency, ['sufficient', 'partial', 'insufficient'])) {
    return 'contextSufficiency';
  }
  if (!isStatement(response.reply)) return 'reply';
  if (response.titleSuggestion !== undefined && (
    typeof response.titleSuggestion !== 'string'
    || response.titleSuggestion.trim() !== response.titleSuggestion
    || response.titleSuggestion.length === 0
    || response.titleSuggestion.length > COACHING_GATEWAY_LIMITS.maxTitleSuggestionLength
  )) return 'titleSuggestion';

  if (response.mode === 'coach') {
    if (!isOneOf(response.relevance, ['career-relevant', 'adjacent'])) return 'relevance';
    if (!isOneOf(response.contextSufficiency, ['sufficient', 'partial'])) return 'contextSufficiency';
    if (!isOneOf(response.stance, ['mirror', 'nudge', 'challenge', 'direct'])) return 'stance';
    const invalidExplanation = explanationViolation(response.explanation, response.stance);
    if (invalidExplanation !== null) return invalidExplanation;
    if (response.proposal !== null) {
      const invalidProposal = coachingProposalViolation(response.proposal);
      if (invalidProposal !== null) return invalidProposal;
    }
  } else if (response.mode === 'clarify') {
    if (response.contextSufficiency !== 'insufficient') return 'contextSufficiency';
    if (response.stance !== null) return 'stance';
    if (response.proposal !== null) return 'proposal';
    const invalidExplanation = explanationViolation(response.explanation, null);
    if (invalidExplanation !== null) return invalidExplanation;
  } else {
    if (response.relevance !== 'outside-scope') return 'relevance';
    if (!isOneOf(response.contextSufficiency, ['sufficient', 'partial'])) return 'contextSufficiency';
    if (response.stance !== null) return 'stance';
    if (response.proposal !== null) return 'proposal';
    const invalidExplanation = explanationViolation(response.explanation, null);
    if (invalidExplanation !== null) return invalidExplanation;
  }
  return usageViolation(response.usage);
}
