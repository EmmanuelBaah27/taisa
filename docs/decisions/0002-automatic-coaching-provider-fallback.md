# 0002: Automatically Fall Back Between Coaching Providers

**Status:** Accepted

**Date:** 2026-08-21

## Context

Taisa already has provider-neutral OpenAI and Anthropic coaching adapters, but runtime selection is
manual. A rate limit, outage, authentication problem, or depleted provider balance can therefore
interrupt coaching until an agent changes configuration and restarts the backend.

## Decision drivers

- Coaching should remain available when either configured provider is operationally unavailable.
- Baah authorizes the same bounded coaching request to be sent automatically to the alternate
  provider after a primary operational failure.
- Automatic recovery must not bypass privacy, schema, safety, or spend boundaries.
- Either provider may be configured as primary.
- Both providers need an equivalent measured quality floor, not identical wording.

## Considered options

1. A composite provider with a combined conservative reservation and one fallback.
2. Independent attempt reservations plus a new cumulative request ledger.
3. Global runtime switching that affects only later requests.

## Decision

Use a composite provider ordered by `TAISA_COACHING_PROVIDER`. It makes one primary call and at
most one alternate-provider call for positively allowlisted operational failures. Reserve the
combined conservative maximum before either call and settle each attempt as a separate
content-free receipt within that request reservation.

Both providers must independently pass the same versioned automated evaluation thresholds and
manual usefulness, grounding, privacy, and safety review before either is enabled as primary or
fallback.

## Consequences

- Provider outages no longer require a manual provider switch for each incident.
- Both providers' complete configuration and credentials become startup requirements.
- Conservative combined reservation may reject a request even when one provider alone would fit;
  this is the cost of guaranteeing the complete request stays below `$0.05`.
- An operational primary failure may still consume budget before the fallback responds.
- Model, prompt, schema, rubric, or material pricing changes require renewed parity evidence.
- Transcription and legacy AI routes remain unchanged.

## Follow-ups

- Implement request-scoped multi-attempt reservation and recovery.
- Add content-free provider error classification and composite orchestration.
- Make the existing manual usefulness threshold enforceable in parity artifacts.
- Update canonical architecture and API documents during Review.
- Verify the exact implementation revision in the canonical preview runtime before device QA.

## References

- `docs/features/automatic-provider-fallback.md`
- `docs/superpowers/specs/2026-08-21-automatic-provider-fallback-design.md`
- `backend/src/evals/coaching/run.ts`
