# Automatic Coaching Provider Fallback — QA Notes

## 2026-08-22 — OpenAI parity gate failed

**Preview revision:** `60c25398b58d352fe7071036355e9ae7a7bb7b8b`

**Evaluation pack:** `2026-08-13.v3`

**Spend:** 26 OpenAI scenarios completed for `$0.011621`; the hard cap was `$0.04`.
Anthropic was not called after OpenAI failed the automated gate.

### Automated evidence

- Schema compliance: `1.000` (required `1.000`)
- Memory correctness: `0.885` (required `0.900`)
- Action quality: `0.654` (required `0.800`)
- Continuity conflict detection: `0.000` (required `0.700`)
- Guardrail failures: missing video, missing meeting, adjacent fatigue, and partial work

### Offline audit

The artifact contained both provider-response defects and pack defects:

- The provider misclassified explicit work signals, adjacent personal context, and partially
  sufficient work context.
- The provider did not consistently emit grounded support or outcome proposals and did not choose
  Challenge for explicit goal conflicts.
- A direct workplace explanation invented rationale not supplied by the synthetic user.
- The pack incorrectly required new goal-memory proposals when an existing goal already captured
  the subject.
- The pack treated ambiguous history as confirmed and treated personal fatigue as career-relevant
  solely because career memory was present, contrary to the approved relevance boundary.

### Remediation

- Version the corrected pack as `2026-08-25.v4`; prior evidence remains invalid.
- Make scenario expectations explicit for grounded outcomes, safe clarification, and existing
  memory support.
- Strengthen the shared Senior Self decision and proposal rules without provider-specific wording.
- Keep governed proposals optional; scenarios that measure support now state explicit corroboration,
  and an underspecified professional role remains career-relevant while requiring clarification.
- Run deterministic tests and code review before requesting a separately capped OpenAI rerun.

## Current QA state

Review remediation is in progress. Do not run Anthropic parity evaluation or merge to `main`
until OpenAI passes the corrected automated and manual gates.
