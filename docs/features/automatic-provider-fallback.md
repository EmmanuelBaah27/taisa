# Automatic Coaching Provider Fallback

**Tier:** Full

**Track:** Platform

**Status:** Build complete; Review + QA pending

**Owner:** Baah

## What is it?

Taisa may use either OpenAI or Anthropic as its configured primary coaching provider. When that
provider has an operational outage, Taisa automatically makes one attempt with the other provider
without requiring Baah to ask for a runtime switch.

## Why now?

The provider-neutral coaching adapters already exist, but selecting a provider is currently a
manual runtime operation. That makes device QA and daily use depend on an agent being available
when a provider is rate-limited, remotely unavailable, denied by provider authentication or
permission, or out of credit. Local configuration remains fail-closed and never triggers fallback.

## Acceptance criteria

- [x] `TAISA_COACHING_PROVIDER=openai` uses OpenAI first and Anthropic as the fallback.
- [x] `TAISA_COACHING_PROVIDER=anthropic` uses Anthropic first and OpenAI as the fallback.
- [x] Taisa falls back at most once and only for an allowlisted operational failure.
- [x] Invalid requests, policy or safety rejections, invalid structured output, local
      configuration errors, and cost-limit failures never trigger fallback.
- [x] The conservative maximum cost of both possible attempts is checked before either provider
      is called.
- [x] One complete coaching request cannot exceed `$0.05`; durable daily and monthly ceilings
      remain `$1` and `$10`.
- [x] Logs and public errors remain content-free and do not expose provider payloads or secrets.
- [x] The successful response records the provider that produced it without changing the mobile
      coaching response contract.
- [ ] OpenAI and Anthropic must each pass the same automated coaching rubric and manual usefulness,
      grounding, privacy, and safety review before being enabled as either primary or fallback.
- [x] Both provider orders and every fallback/no-fallback class are covered without paid provider
      calls in the automated test suite.
- [ ] The verified implementation commit is integrated into and pushed to `preview/taisa`, and the
      persistent QA backend is confirmed to serve that exact revision before device QA.

## Platform dependencies

None. This extends the existing stateless provider abstraction, structured coaching contract,
evaluation pack, and durable cost ledger.

## Out of scope

- More than two coaching providers or more than one fallback attempt.
- Hedged or parallel provider calls.
- Using a second provider to judge every live response.
- Falling back because one provider's valid answer is stylistically different.
- Provider fallback for transcription or legacy AI routes.
- Changing the mobile UI or public coaching response schema.

## Closeout

- **Actual outcome:** Implemented ordered OpenAI/Anthropic coaching with one allowlisted automatic
  fallback, an atomic combined request reservation, content-free failure handling, and enforceable
  per-provider manual review plus parity decisions.
- **Plan deviations:** Paid provider evaluation was deliberately not run because it requires a
  separate explicit budget approval.
- **Learnings and decisions:** See `docs/decisions/0002-automatic-coaching-provider-fallback.md`.
- **Remaining debt:** Complete paid OpenAI and Anthropic parity review, integrate the verified
  revision into `preview/taisa`, confirm the persistent runtime revision, and complete device QA.
- **Canonical docs updated:** `SETUP.md`, `docs/architecture.md`, and `docs/api.md` document the
  implemented provider pair, reservation, fallback policy, spend ceilings, and parity workflow.
- **PR and merge evidence:** Pending Ship.
