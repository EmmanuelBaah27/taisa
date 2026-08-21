# Automatic Coaching Provider Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let either configured coaching provider fall back once to the other for operational failures while enforcing one shared request budget and an equal provider-quality release gate.

**Architecture:** A request-scoped multi-attempt ledger reservation holds the combined conservative maximum before any provider work. A composite coaching provider calls the configured primary once, classifies failures through a content-free allowlist, and calls the alternate once only for operational failures; the route settles each attempt against the original reservation. The existing evaluation pack gains an enforceable manual-review result and a parity combiner that requires both providers to pass the same thresholds.

**Tech Stack:** TypeScript, Node.js, Express, Jest, Zod, SQLite (`better-sqlite3`), OpenAI SDK, Anthropic SDK, React Native mobile contract tests

**Spec:** `docs/superpowers/specs/2026-08-21-automatic-provider-fallback-design.md`

## Global Constraints

- `TAISA_COACHING_PROVIDER` selects either `openai` or `anthropic`; the other provider is the one automatic fallback.
- Make at most one primary call and one fallback call; provider SDK retries stay disabled.
- Fall back only for network/timeout failures, HTTP `408`, `409`, `429`, `5xx`, and recognized provider rate-limit, overload, authentication, permission, billing, or unavailable errors.
- Never fall back for request validation, local configuration, spend rejection, policy/safety rejection, invalid provider requests outside the allowlisted statuses, invalid structured output, or unknown errors.
- The combined conservative maximum must pass `$0.05` per complete request, `$1` per UTC day, and `$10` per UTC month before either provider call.
- Store and log no prompt, transcript, response, provider payload, provider error message, or secret.
- Keep the public coaching request/response schema and mobile UI unchanged.
- Use the existing synthetic evaluation scenarios and thresholds; manual usefulness must average at least `0.8` independently for each provider.
- Ordinary automated tests use deterministic provider fakes and make no paid API calls.
- Do not modify unrelated worktrees or merge `preview/taisa` into `main`.

---

## File Structure

- `backend/src/services/usage/costLedger.ts` — add atomic request-scoped multi-attempt reservations and conservative restart recovery.
- `backend/src/services/coaching/providerFailure.ts` — classify only allowlisted, content-free operational failures.
- `backend/src/services/coaching/fallbackProvider.ts` — order primary/fallback providers and report attempt outcomes without owning persistence.
- `backend/src/services/coaching/provider.ts` — validate both provider configurations and construct the fallback pair.
- `backend/src/services/coaching/coachingGateway.ts` — build one prompt, expose both maximum estimates, and invoke the composite provider.
- `backend/src/routes/coaching.ts` — reserve the combined maximum, settle attempt outcomes, and retain the public contract.
- `backend/src/evals/coaching/run.ts` — validate completed manual review and combine OpenAI/Anthropic evidence into one parity decision.
- `backend/src/evals/coaching/review.ts` — validate completed manual review and emit one content-free provider decision.
- `backend/src/evals/coaching/parity.ts` — combine OpenAI and Anthropic decisions into one release decision.
- `backend/.env.example`, `SETUP.md`, `docs/architecture.md`, `docs/api.md` — document current provider, fallback, budget, and quality-gate behavior.
- Existing backend and mobile test files — protect ledger, orchestration, privacy, evaluation, route, and portable response behavior.

### Task 1: Request-scoped multi-attempt cost reservation

**Files:**
- Modify: `backend/src/services/usage/costLedger.ts`
- Test: `backend/src/__tests__/privacy.middleware.test.ts`

**Interfaces:**
- Consumes: existing `UsageReceipt`, `CostCeilings`, SQLite receipt/reservation tables.
- Produces:

```ts
export interface AttemptEstimate {
  attemptId: 'primary' | 'fallback';
  receipt: UsageReceipt;
}

export interface AttemptSettlement {
  attemptId: AttemptEstimate['attemptId'];
  receipt?: UsageReceipt;
}

export interface MultiAttemptCostReservation {
  beginAttempt(attemptId: AttemptEstimate['attemptId']): void;
  settleAttempt(settlement: AttemptSettlement): void;
  release(): void;
}

export interface UsageLedger {
  // existing members remain
  reserveAttempts(
    estimates: readonly AttemptEstimate[],
    ceilings: CostCeilings,
    reservedAt?: Date,
  ): MultiAttemptCostReservation;
}
```

- [ ] **Step 1: Write failing ledger tests for the combined ceiling and settlement paths**

Add tests that use literal receipts and assert observable ledger rows:

```ts
test('reserves both attempt maxima as one request before provider work', () => {
  const ledger = new CostLedger();
  const attempts = [
    { attemptId: 'primary' as const, receipt: { provider: 'openai' as const, model: 'o', estimatedCostUsd: 0.03 } },
    { attemptId: 'fallback' as const, receipt: { provider: 'anthropic' as const, model: 'a', estimatedCostUsd: 0.02 } },
  ];
  const reservation = ledger.reserveAttempts(attempts, {
    perRequestUsd: 0.05, dailyUsd: 1, monthlyUsd: 10,
  });
  expect(() => ledger.reserveUsage(
    { provider: 'openai', model: 'next', estimatedCostUsd: 0.96 },
    { perRequestUsd: 1, dailyUsd: 1, monthlyUsd: 10 },
  )).toThrow(CostLimitError);
  reservation.release();
  ledger.close();
});

test('rejects the whole request when combined attempt maxima exceed per-request ceiling', () => {
  const ledger = new CostLedger();
  expect(() => ledger.reserveAttempts([
    { attemptId: 'primary', receipt: { provider: 'openai', model: 'o', estimatedCostUsd: 0.03 } },
    { attemptId: 'fallback', receipt: { provider: 'anthropic', model: 'a', estimatedCostUsd: 0.021 } },
  ], { perRequestUsd: 0.05, dailyUsd: 1, monthlyUsd: 10 })).toThrow(CostLimitError);
  expect(ledger.listUsage()).toEqual([]);
  ledger.close();
});

test('records actual primary success and no unused fallback estimate', () => {
  const ledger = new CostLedger();
  const reservation = ledger.reserveAttempts(attemptEstimates, ceilings);
  reservation.beginAttempt('primary');
  reservation.settleAttempt({ attemptId: 'primary', receipt: primaryActual });
  reservation.release();
  expect(ledger.listUsage().map(({ receipt }) => receipt)).toEqual([primaryActual]);
  ledger.close();
});

test('records failed primary estimate and actual fallback usage separately', () => {
  const ledger = new CostLedger();
  const reservation = ledger.reserveAttempts(attemptEstimates, ceilings);
  reservation.beginAttempt('primary');
  reservation.settleAttempt({ attemptId: 'primary' });
  reservation.beginAttempt('fallback');
  reservation.settleAttempt({ attemptId: 'fallback', receipt: fallbackActual });
  reservation.release();
  expect(ledger.listUsage().map(({ receipt }) => receipt)).toEqual([
    attemptEstimates[0].receipt,
    fallbackActual,
  ]);
  ledger.close();
});
```

Also add restart coverage: an in-flight request with primary begun and fallback not begun becomes the primary estimate only; an in-flight fallback becomes both conservative estimates. Test duplicate/unknown/out-of-order attempt IDs fail without corrupting receipts.

- [ ] **Step 2: Run the focused ledger tests and verify RED**

Run:

```bash
cd backend && npm test -- privacy.middleware --runInBand
```

Expected: FAIL because `reserveAttempts` and the multi-attempt settlement interfaces do not exist.

- [ ] **Step 3: Implement the minimal transactional multi-attempt reservation**

Represent the request and attempts explicitly in SQLite:

```sql
CREATE TABLE IF NOT EXISTS cost_request_reservations (
  id TEXT PRIMARY KEY,
  recorded_at TEXT NOT NULL,
  estimated_cost_usd REAL NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('pending', 'in_flight'))
);
CREATE TABLE IF NOT EXISTS cost_attempt_reservations (
  request_id TEXT NOT NULL,
  attempt_id TEXT NOT NULL CHECK(attempt_id IN ('primary', 'fallback')),
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  input_tokens INTEGER,
  output_tokens INTEGER,
  estimated_cost_usd REAL NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('pending', 'in_flight', 'settled')),
  PRIMARY KEY (request_id, attempt_id),
  FOREIGN KEY (request_id) REFERENCES cost_request_reservations(id) ON DELETE CASCADE
);
```

Enable `PRAGMA foreign_keys = ON`. `reserveAttempts` sanitizes exactly two uniquely named estimates, sums their costs, applies the per-request ceiling to the sum, includes the sum in daily/monthly reservation totals, and inserts the request plus both attempts in one immediate transaction. `beginAttempt` enforces `primary` before `fallback`. `settleAttempt` writes actual usage when supplied and the attempt estimate otherwise. `release` deletes unused pending attempts and the request row. Restart reconciliation consumes estimates only for attempts whose state proves provider work began, then deletes the recovered request atomically.

Keep `reserveUsage` behavior unchanged for transcription and evaluation callers.

- [ ] **Step 4: Run ledger tests and verify GREEN**

Run:

```bash
cd backend && npm test -- privacy.middleware coaching.eval --runInBand
```

Expected: both suites pass; existing single-attempt reservation behavior remains green.

- [ ] **Step 5: Commit the ledger slice**

```bash
git add backend/src/services/usage/costLedger.ts backend/src/__tests__/privacy.middleware.test.ts
git commit -m "feat: reserve coaching fallback attempts atomically"
```

### Task 2: Content-free operational failure classification

**Files:**
- Create: `backend/src/services/coaching/providerFailure.ts`
- Test: `backend/src/__tests__/coachingGateway.test.ts`

**Interfaces:**
- Consumes: thrown SDK/network values as `unknown`.
- Produces:

```ts
export type OperationalFailureClass =
  | 'timeout' | 'network' | 'rate_limit' | 'overloaded'
  | 'authentication' | 'permission' | 'billing' | 'unavailable';

export function classifyOperationalProviderFailure(
  error: unknown,
): OperationalFailureClass | null;
```

- [ ] **Step 1: Write the classifier table test**

Use literal, message-free error shapes:

```ts
test.each([
  [{ status: 408 }, 'timeout'],
  [{ status: 409 }, 'unavailable'],
  [{ status: 429, type: 'rate_limit_error' }, 'rate_limit'],
  [{ status: 503, type: 'provider_error' }, 'unavailable'],
  [{ type: 'overloaded_error' }, 'overloaded'],
  [{ type: 'authentication_error' }, 'authentication'],
  [{ type: 'permission_error' }, 'permission'],
  [{ type: 'billing_error' }, 'billing'],
  [{ code: 'ETIMEDOUT' }, 'timeout'],
  [{ code: 'ECONNRESET' }, 'network'],
])('classifies an allowlisted operational failure', (error, expected) => {
  expect(classifyOperationalProviderFailure(error)).toBe(expected);
});

test.each([
  { status: 400, type: 'invalid_request_error' },
  { status: 403, type: 'safety_error' },
  { type: 'content_policy_error' },
  { code: 'UNKNOWN_PRIVATE_CODE' },
  new Error('message text is never classification input'),
])('fails closed for non-operational or unknown errors', (error) => {
  expect(classifyOperationalProviderFailure(error)).toBeNull();
});
```

- [ ] **Step 2: Run the focused classifier test and verify RED**

Run:

```bash
cd backend && npm test -- coachingGateway --runInBand
```

Expected: FAIL because `providerFailure.ts` and its export do not exist.

- [ ] **Step 3: Implement allowlist-only structural classification**

Normalize only `status`, `type`, `code`, and `name` when they are primitive strings/numbers. Check explicit policy/safety and invalid-request deny rules before operational status rules. Do not read `message`, `cause`, response bodies, headers, or serialized error content.

```ts
export function classifyOperationalProviderFailure(error: unknown) {
  const value = asRecord(error);
  if (DENIED_TYPES.has(stringField(value, 'type'))) return null;
  const status = integerField(value, 'status');
  if (status === 408) return 'timeout';
  if (status === 409) return 'unavailable';
  if (status === 429) return 'rate_limit';
  if (status !== null && status >= 500 && status <= 599) return 'unavailable';
  return classifyKnownTypeOrNetworkCode(value);
}
```

- [ ] **Step 4: Run classifier tests and verify GREEN**

Run:

```bash
cd backend && npm test -- coachingGateway legacyAi.routes.privacy --runInBand
```

Expected: both suites pass and no private message text appears in assertions or diagnostics.

- [ ] **Step 5: Commit the classifier**

```bash
git add backend/src/services/coaching/providerFailure.ts backend/src/__tests__/coachingGateway.test.ts
git commit -m "feat: classify coaching provider outages safely"
```

### Task 3: Composite provider and dual-provider configuration

**Files:**
- Create: `backend/src/services/coaching/fallbackProvider.ts`
- Modify: `backend/src/services/coaching/provider.ts`
- Modify: `backend/src/services/coaching/coachingGateway.ts`
- Test: `backend/src/__tests__/coachingGateway.test.ts`

**Interfaces:**
- Consumes: `ProviderRegistry`, both validated provider configs, `classifyOperationalProviderFailure`.
- Produces:

```ts
export interface ProviderAttemptOutcome {
  attemptId: 'primary' | 'fallback';
  providerId: CoachingProviderId;
  result?: ProviderCoachingResult;
  failureClass?: OperationalFailureClass;
}

export interface FallbackCoachingResult {
  result: ProviderCoachingResult;
  attempts: readonly ProviderAttemptOutcome[];
}

export interface FallbackCoachingProvider {
  readonly primaryId: CoachingProviderId;
  readonly fallbackId: CoachingProviderId;
  estimateMaximumAttempts(input: ProviderCoachingInput): readonly AttemptEstimate[];
  respond(
    input: ProviderCoachingInput,
    observer: ProviderAttemptObserver,
  ): Promise<FallbackCoachingResult>;
}

export interface ProviderAttemptObserver {
  beginAttempt(attemptId: AttemptEstimate['attemptId']): void;
  settleAttempt(settlement: AttemptSettlement): void;
}

export function getConfiguredFallbackProvider(
  environment?: CoachingEnvironment,
  providers?: ProviderRegistry,
): FallbackCoachingProvider;
```

- [ ] **Step 1: Replace the single-selection test with failing primary/fallback behavior tests**

Cover both orders and the call boundary:

```ts
test.each(['openai', 'anthropic'] as const)(
  '%s primary success calls no fallback and reports one attempt',
  async (primaryId) => {
    const provider = getConfiguredFallbackProvider(environment(primaryId), providers);
    const outcome = await provider.respond(providerInput, observer);
    expect(outcome.attempts).toEqual([
      expect.objectContaining({ attemptId: 'primary', providerId: primaryId }),
    ]);
    expect(providers[primaryId].respond).toHaveBeenCalledTimes(1);
    expect(providers[other(primaryId)].respond).not.toHaveBeenCalled();
  },
);

test.each(operationalFailures)(
  'one %s primary failure invokes the alternate exactly once',
  async (_name, failure) => {
    providers.openai.respond = jest.fn().mockRejectedValue(failure);
    const outcome = await getConfiguredFallbackProvider(
      environment('openai'), providers,
    ).respond(providerInput, observer);
    expect(outcome.result.usage.provider).toBe('anthropic');
    expect(outcome.attempts.map(({ attemptId }) => attemptId)).toEqual([
      'primary', 'fallback',
    ]);
    expect(providers.anthropic.respond).toHaveBeenCalledTimes(1);
  },
);

test.each(nonOperationalFailures)(
  'a non-operational primary failure never invokes fallback',
  async (failure) => {
    providers.openai.respond = jest.fn().mockRejectedValue(failure);
    await expect(getConfiguredFallbackProvider(
      environment('openai'), providers,
    ).respond(providerInput, observer)).rejects.toBe(failure);
    expect(providers.anthropic.respond).not.toHaveBeenCalled();
  },
);
```

Add tests that both maximum estimates are required, retain their provider/model identity, and are ordered `primary`, `fallback`. Assert startup fails when any config field for either provider is absent.

- [ ] **Step 2: Run gateway tests and verify RED**

Run:

```bash
cd backend && npm test -- coachingGateway --runInBand
```

Expected: FAIL because the composite interfaces and `getConfiguredFallbackProvider` do not exist.

- [ ] **Step 3: Implement the composite provider and dual config validation**

Export `readProviderConfig` or add `getConfiguredProviderPairSettings` without weakening validation:

```ts
export function getConfiguredProviderPairSettings(environment = process.env) {
  const primaryId = requireProviderId(environment.TAISA_COACHING_PROVIDER);
  const fallbackId = primaryId === 'openai' ? 'anthropic' : 'openai';
  return {
    primaryId,
    fallbackId,
    configs: {
      openai: readProviderConfig(environment, 'openai'),
      anthropic: readProviderConfig(environment, 'anthropic'),
    },
  };
}
```

`fallbackProvider.respond` calls `observer.beginAttempt` immediately before each provider invocation and `observer.settleAttempt` immediately after its success or failure. Each existing provider adapter already parses through `CoachingResponsePayloadSchema`; a Zod failure is not operational, reaches the gateway's existing `RecoverableCoachingError` mapping, and never falls back. Operational failures append a content-free attempt outcome and call the alternate once. If fallback fails, throw a content-free wrapper containing only both failure classes and attempt IDs so route diagnostics never receive raw provider payloads.

- [ ] **Step 4: Run gateway tests and verify GREEN**

Run:

```bash
cd backend && npm test -- coachingGateway coaching.contract --runInBand
```

Expected: both suites pass for both provider orders and shared schema behavior.

- [ ] **Step 5: Commit composite orchestration**

```bash
git add backend/src/services/coaching/providerFailure.ts backend/src/services/coaching/fallbackProvider.ts backend/src/services/coaching/provider.ts backend/src/services/coaching/coachingGateway.ts backend/src/__tests__/coachingGateway.test.ts
git commit -m "feat: add automatic coaching provider fallback"
```

### Task 4: Route-level reservation, settlement, and privacy behavior

**Files:**
- Modify: `backend/src/routes/coaching.ts`
- Modify: `backend/src/services/coaching/coachingGateway.ts`
- Test: `backend/src/__tests__/coaching.routes.test.ts`
- Test: `backend/src/__tests__/privacy.middleware.test.ts`

**Interfaces:**
- Consumes: `estimateConfiguredCoachingAttempts(request)`, `requestCoaching(request)`, `reserveAttempts`.
- Produces:

```ts
export function estimateConfiguredCoachingAttempts(
  request: CoachingRequest,
  environment?: CoachingEnvironment,
): readonly AttemptEstimate[];

export interface CoachingExecution {
  response: CoachingResponse;
  attempts: readonly ProviderAttemptOutcome[];
}

export async function requestCoaching(
  request: CoachingRequest,
  provider?: FallbackCoachingProvider,
  observer?: ProviderAttemptObserver,
): Promise<CoachingExecution>;
```

- [ ] **Step 1: Write failing route behavior tests**

Update route mocks to return attempt outcomes and assert exact ordering:

```ts
test('reserves both maxima before primary work and settles primary success', async () => {
  const response = await request(app).post('/api/v1/coaching/respond').send(validRequest);
  expect(response.status).toBe(200);
  expect(usageLedger.reserveAttempts).toHaveBeenCalledWith(
    [primaryEstimate, fallbackEstimate],
    { perRequestUsd: 0.05, dailyUsd: 1, monthlyUsd: 10 },
  );
  expect(reservation.beginAttempt).toHaveBeenCalledWith('primary');
  expect(reservation.settleAttempt).toHaveBeenCalledWith({
    attemptId: 'primary', receipt: primaryActual,
  });
  expect(reservation.beginAttempt).not.toHaveBeenCalledWith('fallback');
});

test('settles failed primary conservatively then commits fallback actual usage', async () => {
  gateway.requestCoaching.mockResolvedValueOnce(fallbackExecution);
  const response = await request(app).post('/api/v1/coaching/respond').send(validRequest);
  expect(response.body.data.usage.provider).toBe('anthropic');
  expect(reservation.settleAttempt.mock.calls).toEqual([
    [{ attemptId: 'primary' }],
    [{ attemptId: 'fallback', receipt: fallbackActual }],
  ]);
});

test('combined ceiling rejection calls neither provider', async () => {
  usageLedger.reserveAttempts.mockImplementationOnce(() => {
    throw new usageLedger.CostLimitError();
  });
  const response = await request(app).post('/api/v1/coaching/respond').send(validRequest);
  expect(response.status).toBe(429);
  expect(gateway.requestCoaching).not.toHaveBeenCalled();
});
```

Add a privacy test whose two raw provider errors contain different secrets and assert neither the response nor captured `console` calls contain either secret.

- [ ] **Step 2: Run route/privacy tests and verify RED**

Run:

```bash
cd backend && npm test -- coaching.routes privacy.middleware --runInBand
```

Expected: FAIL because the route still reserves and settles only one provider call.

- [ ] **Step 3: Wire the route to the composite execution lifecycle**

Reserve both estimates before invoking `requestCoaching`. Pass the returned `MultiAttemptCostReservation` as the exact `ProviderAttemptObserver`, so `beginAttempt` executes immediately before each provider call and `settleAttempt` immediately after its success/failure. Do not wait until both calls finish to mark an attempt in flight; restart recovery depends on this ordering.

Keep `CostLimitError`, `CostConfigurationError`, and `RecoverableCoachingError` mappings unchanged. Add only content-free failure classifications to the operational code. Return `execution.response`, not attempt metadata, so the public schema remains unchanged.

- [ ] **Step 4: Run route/privacy tests and verify GREEN**

Run:

```bash
cd backend && npm test -- coaching.routes coachingGateway privacy.middleware --runInBand
```

Expected: all suites pass with exact provider call counts and content-free failures.

- [ ] **Step 5: Commit route integration**

```bash
git add backend/src/routes/coaching.ts backend/src/services/coaching/coachingGateway.ts backend/src/__tests__/coaching.routes.test.ts backend/src/__tests__/privacy.middleware.test.ts
git commit -m "feat: enforce shared budget across coaching fallback"
```

### Task 5: Enforce provider-parity evaluation evidence

**Files:**
- Modify: `backend/src/evals/coaching/run.ts`
- Create: `backend/src/evals/coaching/review.ts`
- Create: `backend/src/evals/coaching/parity.ts`
- Modify: `backend/package.json`
- Test: `backend/src/__tests__/coaching.eval.test.ts`

**Interfaces:**
- Consumes: existing `buildManualReviewArtifact`, `COACHING_EVALUATION_THRESHOLDS`, and completed review JSON.
- Produces:

```ts
export interface CompletedManualReview {
  scenarioId: string;
  manualUsefulness: number;
  inventedReferent: boolean;
  inventedEmotion: boolean;
  inventedParticipantOrPurpose: boolean;
  clarificationQuestionNeutral: boolean | null;
  proposalsGroundedInSupportedObservation: boolean | null;
}

export interface ProviderEvaluationDecision {
  provider: CoachingProviderId;
  packVersion: string;
  automatedPassed: boolean;
  manualPassed: boolean;
  passed: boolean;
}

export function validateCompletedManualReview(
  artifact: ReturnType<typeof buildManualReviewArtifact>,
  reviews: readonly CompletedManualReview[],
): ProviderEvaluationDecision;

export function buildProviderParityDecision(
  openai: ProviderEvaluationDecision,
  anthropic: ProviderEvaluationDecision,
): { packVersion: string; passed: boolean; providers: readonly ProviderEvaluationDecision[] };

export function runReviewCli(
  argv: string[],
  io?: ReviewCliIo,
): 0 | 1;

export function runParityCli(
  argv: string[],
  io?: ParityCliIo,
): 0 | 1;
```

- [ ] **Step 1: Write failing manual and parity gate tests**

```ts
test('manual provider review passes only at the shared usefulness and grounding floor', () => {
  const decision = validateCompletedManualReview(passingArtifact('openai'), passingReviews);
  expect(decision).toEqual({
    provider: 'openai', packVersion: '2026-08-13.v3',
    automatedPassed: true, manualPassed: true, passed: true,
  });
});

test.each([
  ['usefulness below 0.8', reviewsWithUsefulness(0.79)],
  ['invented referent', reviewsWith({ inventedReferent: true })],
  ['invented emotion', reviewsWith({ inventedEmotion: true })],
  ['invented participant', reviewsWith({ inventedParticipantOrPurpose: true })],
  ['non-neutral clarification', reviewsWith({ clarificationQuestionNeutral: false })],
  ['ungrounded proposal', reviewsWith({ proposalsGroundedInSupportedObservation: false })],
])('manual provider review fails for %s', (_name, reviews) => {
  expect(validateCompletedManualReview(passingArtifact('openai'), reviews).passed).toBe(false);
});

test('parity requires both providers on the same pack version to pass', () => {
  expect(buildProviderParityDecision(openAIPass, anthropicPass).passed).toBe(true);
  expect(buildProviderParityDecision(openAIPass, { ...anthropicPass, passed: false }).passed).toBe(false);
  expect(() => buildProviderParityDecision(
    openAIPass, { ...anthropicPass, packVersion: 'other' },
  )).toThrow('Provider evaluation pack versions must match');
});
```

- [ ] **Step 2: Run evaluation tests and verify RED**

Run:

```bash
cd backend && npm test -- coaching.eval --runInBand
```

Expected: FAIL because completed manual review and parity decision functions do not exist.

- [ ] **Step 3: Implement strict completed-review validation and parity combination**

Require exactly one completed review for every scenario ID in the artifact and no extras. Average literal `manualUsefulness` values and compare against `manualUsefulnessMinimum`. Treat every applicable false grounding/neutrality flag and every true invention flag as failure. `passed` is `automatedPassed && manualPassed`. Parity passes only when provider IDs are exactly OpenAI and Anthropic, pack versions match, and both decisions pass.

Add these scripts and exact CLI contracts:

```json
{
  "eval:coaching:review": "ts-node src/evals/coaching/review.ts",
  "eval:coaching:parity": "ts-node src/evals/coaching/parity.ts"
}
```

```bash
npm run eval:coaching:review --workspace=backend -- \
  --artifact=<draft-review.json> \
  --completed-review=<completed-review.json> \
  --decision-output=<provider-decision.json>
npm run eval:coaching:parity --workspace=backend -- \
  --openai-decision=<openai-decision.json> \
  --anthropic-decision=<anthropic-decision.json> \
  --parity-output=<parity-decision.json>
```

Each CLI uses injected read/write functions in tests, requires every flag exactly once, writes outputs with `flag: 'wx'`, emits only `EVAL_COACHING_REVIEW_FAILED` or `EVAL_COACHING_PARITY_FAILED` on failure, and returns `0` only for a passing decision. Provider generation remains through the existing explicit, budgeted `eval:coaching -- --provider=<id> --max-cost-usd=<budget>` command. Serialized provider/parity decisions contain only provider IDs, pack version, thresholds, and booleans—never synthetic prompts or response text.

- [ ] **Step 4: Run evaluation tests and verify GREEN**

Run:

```bash
cd backend && npm test -- coaching.eval --runInBand
```

Expected: suite passes; malformed, incomplete, mismatched-version, or one-provider evidence fails closed.

- [ ] **Step 5: Commit the parity gate**

```bash
git add backend/src/evals/coaching/run.ts backend/src/evals/coaching/review.ts backend/src/evals/coaching/parity.ts backend/package.json backend/src/__tests__/coaching.eval.test.ts
git commit -m "feat: enforce coaching provider quality parity"
```

### Task 6: Configuration and canonical documentation

**Files:**
- Modify: `backend/.env.example`
- Modify: `SETUP.md`
- Modify: `docs/architecture.md`
- Modify: `docs/api.md`
- Modify: `docs/features/automatic-provider-fallback.md`

**Interfaces:**
- Consumes: implemented provider pair, fallback policy, ledger behavior, and parity commands.
- Produces: complete deployment configuration and canonical current-behavior documentation.

- [ ] **Step 1: Update configuration and canonical docs**

Set and preserve these non-secret examples:

```dotenv
TAISA_COACHING_PROVIDER=openai
TAISA_AI_COST_CEILING_PER_REQUEST_USD=0.05
TAISA_AI_COST_CEILING_DAILY_USD=1
TAISA_AI_COST_CEILING_MONTHLY_USD=10
```

Document that both provider credential/config blocks are mandatory, the selected provider is primary, fallback happens once for the approved operational allowlist, and the combined maximum is reserved before either call. Update `docs/architecture.md` from “one configured provider call” to the one-primary/optional-one-fallback flow. Update `docs/api.md` without changing its request or response examples. Document the exact paid parity-evaluation workflow and its required explicit budget.

Update the scope status to `Build complete; Review + QA pending` only after implementation verification, and fill only evidence already produced in its Closeout section.

- [ ] **Step 2: Run focused configuration and workflow verification**

Run:

```bash
cd backend && npm test -- coachingGateway coaching.routes coaching.eval --runInBand
cd .. && npm run verify:workflow
git diff --check
```

Expected: all tests and both repository checks pass.

- [ ] **Step 3: Commit configuration and docs**

```bash
git add backend/.env.example SETUP.md docs/architecture.md docs/api.md docs/features/automatic-provider-fallback.md
git commit -m "docs: document automatic coaching fallback"
```

### Task 7: Full verification, review, and exact preview integration

**Files:**
- Test: all changed backend tests and `mobile/src/services/__tests__/coaching.test.ts`
- Modify during Review only if evidence requires it: `docs/features/automatic-provider-fallback.md`

**Interfaces:**
- Consumes: all prior tasks and the Taisa Review + QA workflow.
- Produces: verified implementation commit, review evidence, pushed `preview/taisa` integration, and confirmed QA runtime revision.

- [ ] **Step 1: Run the complete Backend verification row**

Run:

```bash
npm test --workspace=backend -- --runInBand
npm run build --workspace=backend
```

Expected: all backend suites pass and TypeScript exits `0`.

- [ ] **Step 2: Run the explicitly requested focused mobile compatibility checks**

Run:

```bash
cd mobile && npm test -- coaching --runInBand
npm run typecheck
```

Expected: coaching client tests pass for either provider receipt and mobile TypeScript exits `0`.

- [ ] **Step 3: Run repository/privacy checks**

Run:

```bash
npm run verify:workflow
git diff --check origin/main...HEAD
git status --short --branch
```

Inspect the diff for secrets, readable provider content, unrelated files, and accidental public schema changes. Expected: checks pass and only approved feature files differ.

- [ ] **Step 4: Invoke code review and resolve all blocking findings**

Use `superpowers:requesting-code-review`. Re-run the full commands from Steps 1–3 after any fix. Update the scope Closeout with actual outcome, deviations, promoted decision/learning links, canonical docs, and commit evidence; PR/merge fields remain pending until Ship.

- [ ] **Step 5: Commit final review housekeeping**

```bash
git add docs/features/automatic-provider-fallback.md
git commit -m "docs: record coaching fallback review evidence"
```

Skip this commit if Review produces no tracked housekeeping change.

- [ ] **Step 6: Push the verified implementation branch**

```bash
git push -u origin feature/automatic-provider-fallback
```

Expected: remote branch points to the locally verified commit.

- [ ] **Step 7: Integrate the exact verified commits into `preview/taisa`**

First verify the preview worktree is clean and current. Cherry-pick only the feature commits; never merge the preview branch back into the feature branch or `main`:

```bash
git -C .worktrees/preview-taisa status --short --branch
git -C .worktrees/preview-taisa fetch --prune origin
git -C .worktrees/preview-taisa cherry-pick <first-feature-commit>^..<verified-feature-head>
git -C .worktrees/preview-taisa push origin preview/taisa
```

Expected: clean cherry-pick, pushed `origin/preview/taisa`, no unrelated worktree modification. If preview is dirty, conflicts, or its architecture lacks the changed provider boundaries, stop and report rather than overwrite or infer.

- [ ] **Step 8: Apply QA-only environment configuration without committing secrets**

In `.worktrees/preview-taisa/backend/.env`, preserve real secrets and set only these reviewed non-secret values:

```dotenv
TAISA_COACHING_PROVIDER=openai
TAISA_AI_COST_CEILING_PER_REQUEST_USD=0.05
TAISA_AI_COST_CEILING_DAILY_USD=1
TAISA_AI_COST_CEILING_MONTHLY_USD=10
```

Confirm both provider model/pricing/output-cap/overhead blocks and credentials are present without printing secret values. The paid parity evaluation requires a separately approved explicit budget; do not run it merely as part of automated QA.

- [ ] **Step 9: Restart and prove the exact preview revision is served**

Stop only the named persistent backend session, start it again from the preview backend directory, and leave Metro untouched unless its cwd/revision is wrong:

```bash
screen -S taisa-preview-backend -X quit
screen -dmS taisa-preview-backend zsh -lc 'cd /Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa/.worktrees/preview-taisa/backend && npm run dev'
git -C /Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa/.worktrees/preview-taisa rev-parse HEAD
lsof -nP -iTCP:3001 -sTCP:LISTEN
lsof -nP -iTCP:8081 -sTCP:LISTEN
```

Use `lsof -a -p <pid> -d cwd -Fn` for both listeners and confirm both cwd values are inside the same `preview-taisa` worktree. Confirm `git rev-parse HEAD` equals `origin/preview/taisa`. If the canonical workflow has moved Metro to another documented port, use that port and record the evidence rather than starting a competing Metro instance.

- [ ] **Step 10: Hand off device QA and stop at the Ship gate**

Ask Baah to verify a normal OpenAI-primary coaching response and a controlled automatic fallback, then repeat with Anthropic primary. Do not deliberately exhaust credits, expose real content to diagnostics, or manufacture a paid outage without explicit approval. After Baah confirms device QA, invoke `superpowers:finishing-a-development-branch`; only a clear Ship instruction authorizes PR merge and `main` update.
