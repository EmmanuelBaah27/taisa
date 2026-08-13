# Task 2 Report: Ordered Decision Prompt and Gateway Invariants

## Delivered

- Added the ordered Senior Self decision policy: Safety → Relevance → Context sufficiency → Coaching stance.
- Defined `career-relevant`, `adjacent`, and `outside-scope`; missing referents (`this`, `that meeting`, `the video`, and `what happened earlier`) are explicitly not facts.
- Required `clarify` to ask exactly one neutral question without diagnosing emotion; constrained `redirect` to a brief acknowledgement and at most one optional work bridge.
- Preserved Task 1's discriminated `coach | clarify | redirect` response contract. The gateway continues to parse that union strictly and makes no coercive fallback.
- Mobile persists every valid assistant reply but stages proposals only for `coach`; `clarify` and `redirect` create no confirmations, goals, actions, evidence, or memory items.
- Added regression coverage for prompt policy, valid non-coaching replies, and fail-closed malformed `clarify` proposal staging.

## Verification

All commands used local mocks/test databases only; no provider, network, native, or device action was run.

- `cd backend && npm test -- coachingGateway coaching.routes --runInBand` — 63 passed.
- `cd backend && npm run build` — passed.
- `cd mobile && npm test -- privateCapture --runInBand` — 45 passed.
- `cd mobile && npm run typecheck` — passed.
- `cd backend && npm test -- --runInBand` — 185 passed.
- `cd backend && npm run build` — passed.
- `cd mobile && npm test -- --runInBand` — 380 passed.
- `cd mobile && npm run typecheck` — passed.
- Independent code review — no blocking findings.

## Concerns and follow-up

- Physical-device QA remains the next Baah approval gate; it was intentionally not run.
- Pre-existing untracked `backend/taisa-usage-ledger.sqlite`, `-shm`, and `-wal` files were preserved and excluded from this task's commit.

## Correction round 1

- Corrected relevance to be decided from the primary subject of the current user turn before bounded context is consulted. Career profile, history, memory, and evidence cannot make an off-topic turn career-relevant.
- Replaced the abbreviated relevance and sufficiency guidance with the approved mutually exclusive definitions, including the explicit adjacent-work-effect requirement and the separate sufficient, partially sufficient, and insufficient clauses.
- Added an offline fixture-boundary regression: an off-topic question with a populated career profile, work history, and memory produces the valid `redirect` / `outside-scope` structure without a live model call.
- Added prompt assertions for the approved relevance and sufficiency constraints, including no advice/proposals for clarification and proposal grounding limited to the supported portion of partial context.

Fresh correction-round verification:

- Focused: backend 66 tests + build; mobile 45 tests + typecheck.
- Full: backend 188 tests + build; mobile 380 tests + typecheck.
