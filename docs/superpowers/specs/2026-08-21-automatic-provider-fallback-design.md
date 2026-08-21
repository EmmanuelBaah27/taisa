# Automatic Coaching Provider Fallback Design

**Date:** 2026-08-21

**Status:** Approved in conversation; awaiting written-spec review

**Track:** Platform

**Tier:** Full

## Goal

Keep coaching available through a single operational provider outage while preserving Taisa's
provider-neutral response contract, privacy boundary, and exact `$0.05` per-request, `$1` daily,
and `$10` monthly spend ceilings.

## Provider selection

`TAISA_COACHING_PROVIDER` remains required and identifies the primary provider. The alternate
provider is derived deterministically:

| Configured primary | Automatic fallback |
|---|---|
| `openai` | `anthropic` |
| `anthropic` | `openai` |

Startup validates the model, pricing, output cap, structured-output overhead, and credentials
required by both providers. Fallback-enabled service does not start with only one valid provider
configuration because it could not honor its declared resilience or reserve its maximum cost.

Both adapters receive the same `ProviderCoachingInput` produced by `buildSeniorSelfPrompt` and must
return the same `CoachingResponsePayloadSchema`. The mobile request and response contracts do not
change.

## Fallback orchestration

A composite coaching provider owns ordering and the one-fallback limit:

1. Call the configured primary once with SDK retries disabled.
2. Return immediately when the primary produces a valid response.
3. Classify a thrown provider error without inspecting or logging content.
4. If and only if the classification is allowlisted as operational, call the alternate once.
5. Return the alternate's valid response or surface its content-free operational failure.

There are never parallel calls, SDK retries, a third attempt, or fallback based on response style.

### Fallback-eligible failures

- Network connection failure or timeout.
- HTTP `408`, `409`, `429`, or any `5xx` provider response.
- Provider rate-limit, overload, authentication, permission, billing, or service-unavailable error.

Authentication, permission, and billing failures are eligible because Baah explicitly authorized
automatic cross-provider handling and these conditions represent primary-provider unavailability.

### Failures that stop immediately

- Invalid Taisa request or bounded-context validation.
- Local provider/configuration validation.
- Spend reservation or ceiling rejection.
- Provider policy or safety rejection.
- Provider invalid-request errors other than the operational HTTP statuses above.
- Missing, malformed, or schema-invalid structured coaching output.
- Any error not positively recognized by the allowlist.

Unknown failures fail closed. Error classification uses provider SDK status/type/code fields and
never error-message matching, because messages may contain private provider payloads.

## Spend enforcement and accounting

Before either call, the gateway obtains each adapter's conservative maximum usage for the same
prompt and adds their estimated costs. A single reservation for that combined maximum must fit all
three existing ceilings:

- per complete user request: `$0.05`;
- UTC day: `$1`;
- UTC month: `$10`.

If the combined maximum does not fit, the gateway returns the existing cost-limit response and
calls neither provider. This deliberately reserves for the worst case rather than allowing the
fallback to bypass the per-request ceiling.

Accounting follows the actual execution path:

- Primary success commits the primary's actual usage and releases unused fallback capacity.
- Primary operational failure consumes the primary conservative estimate because a provider may
  have charged without returning trustworthy usage.
- Fallback success records its actual usage in addition to the consumed primary estimate.
- Fallback failure consumes its conservative estimate.

The ledger therefore needs one request-scoped reservation that can settle two attempts while
retaining separate content-free provider/model receipts. Settlement is transactional and
restart-safe. The sum settled for the request never exceeds the amount reserved. Existing daily
and monthly totals continue to count receipts plus active reservations atomically.

## Privacy and diagnostics

The fallback receives only the same bounded request context already approved for coaching. No
additional conversation history is loaded. Taisa stores no prompt, transcript, response, provider
payload, or error message in backend SQLite or logs.

Content-free diagnostics may include:

- primary provider identifier;
- fallback provider identifier;
- allowlisted failure classification;
- whether fallback started and whether it succeeded;
- request ID only where the existing privacy contract already permits it;
- content-free usage receipts.

Public errors retain the existing allowlisted operational shape. The public success response's
usage receipt identifies the provider that produced the returned coaching response.

## Provider-parity quality gate

OpenAI and Anthropic use the existing versioned synthetic coaching evaluation pack independently.
Both must pass the same release gate before their configured models or prices are enabled:

1. Every response parses through the shared coaching schema.
2. All existing automated thresholds in `COACHING_EVALUATION_THRESHOLDS` pass.
3. Every guardrail invariant scores `1.0`.
4. Manual usefulness averages at least the existing `0.8` threshold for each provider.
5. Manual review marks every invented referent, emotion, participant, or purpose field false.
6. Clarification questions remain neutral and proposed memory/outcomes remain grounded in supplied
   observations for every applicable scenario.

Evaluation commands require an explicit provider and total budget. They remain separate paid,
human-reviewed release evidence; ordinary Jest tests use deterministic fakes and spend nothing.
A model, prompt, schema, rubric, or material pricing change invalidates prior parity evidence and
requires both providers to be evaluated again.

The fallback mechanism itself is tested with fakes in both provider orders. A live outage is not
manufactured by spending against production providers.

## Error and recovery behavior

- A primary operational failure followed by fallback success is a normal successful response.
- A non-operational primary failure preserves the current recoverable or operational response and
  never calls fallback.
- If both providers fail operationally, the request returns one content-free coaching failure.
- Process interruption settles or recovers the request-scoped reservation conservatively so an
  interrupted in-flight attempt cannot disappear from daily/monthly accounting.
- The client may retry a failed request through its existing durable request behavior; server-side
  fallback does not create an additional mobile interaction.

## Configuration and rollout

`backend/.env.example` defaults `TAISA_COACHING_PROVIDER` to `openai` and documents that both
provider configuration blocks are mandatory. The approved ceiling examples remain exactly
`0.05`, `1`, and `10`.

Rollout order:

1. Verify deterministic backend and mobile compatibility tests on the implementation branch.
2. Run and manually approve the paid parity evaluation for both configured models under a
   separately approved evaluation budget.
3. Commit and push the exact implementation revision.
4. Integrate that commit into `preview/taisa` without merging unrelated preview work to `main`.
5. Restart the persistent QA backend from the preview worktree and confirm its process cwd and
   revision; confirm Metro uses the same preview worktree and revision.
6. Complete device QA with each provider configured as primary and an intentionally controlled,
   non-content-bearing operational failure for the fallback path.
7. After Ship approval, merge the feature pull request into `main`.

## Verification

Automated coverage must demonstrate:

- both provider orders select the correct primary and alternate;
- primary success calls only the primary;
- every allowlisted operational class calls fallback exactly once;
- every stop-immediately class calls fallback zero times;
- unknown errors fail closed;
- primary and fallback structured-output failures do not retry;
- combined maximum reservation happens before either provider call;
- combined maximum above `$0.05`, or beyond `$1`/day or `$10`/month, calls neither provider;
- primary/fallback settlement records the correct separate content-free receipts;
- interrupted reservations recover conservatively;
- public errors and diagnostics contain no provider payload, prompt, response, or secret;
- the public success usage identifies the answering provider;
- the parity artifact cannot pass unless both providers meet identical automated and manual gates;
- existing mobile coaching parsing accepts primary and fallback successes without changes.

Final branch verification follows the Backend row plus the explicitly requested focused mobile
coaching tests and mobile TypeScript check. Device QA is required before Ship.

## Out of scope

- Transcription fallback.
- Legacy Claude route migration.
- More than two providers.
- Parallel, hedged, or speculative provider requests.
- Live per-response model judging.
- Automatic model selection based on coaching style or response quality.
- Mobile UI changes or exposing provider-selection controls.
