# APF-61 Review Blocker Repair Plan

**Primary issue:** APF-61 — Chat detail and recording journey

**Work tier:** Standard delivery with high-risk repair gates because the review found data-loss, compatibility, and durable-retry defects.

**Branch:** `fix/apf61-review-blockers`

**Terminal outcome:** A clean APF-61 repair candidate that has passed the one named physical
interaction, the full verification matrix on that unchanged revision, and final review, ready
for Baah's Ship decision. No merge or canonical-preview publication is authorized by this plan.

## Repair contract

- This plan specializes but cannot supersede `AGENTS.md`, `docs/workflow.md`, or the Taisa
  workflow orchestrator. Any contradiction stops execution before another command or
  verification spend and must be shown to Baah and reconciled first.
- Preserve the accepted chat visuals and interaction decisions; repair only reviewed defects and required shared-system adoption.
- Make every persistence change backward-compatible with schema-v6 partial state and current schema-v7 data. Do not introduce schema v8.
- Use tests that reproduce each failure before changing production code.
- Keep composer/network failures separate from feedback and proposal-action failures.
- Keep the repair candidate non-canonical. Do not publish or overwrite `preview/taisa` before
  Ship; after approval and merge, synchronize the shipped `main` revision one way into preview.

## Design-system inventory and exact gap treatment

Existing shared contracts cover spacing (4/8/12/16/20/24/32), radii, control heights, standard icon sizing, semantic foreground/surface colors, and Central Icons. The reviewed Product surface must adopt those contracts.

The activity indicator currently has four unavailable semantic roles. Add them to the Apple design-system package before changing its consumer:

1. `TaisaActivityIndicatorMetric` for the indicator frame, bar geometry, and inter-bar spacing, preserving the approved rendered dimensions.
2. `TaisaMotion.activityCycle` and `activityStagger` plus the shared animation construction used by the indicator, preserving the approved cadence while honoring Reduce Motion.
3. `TaisaColor.activityWarmAccent` and `activityCoolAccent` as semantic decorative accents owned by the design system, preserving the approved warm/cool appearance.
4. `TaisaTypography.supporting` for the existing 14/20 regular supporting copy. Reuse `navigationLabel` for existing 16/24 medium text; do not add another role.

All chat icons remain Central Icons. No SF Symbol or feature-local icon is permitted.

## Tasks

### 1. Restore the shared coaching-response compatibility boundary

- Add a failing legacy-mobile contract test for a singular `proposal` response.
- Replace the stale `response.proposals` consumer with a narrow compatibility adapter that treats `proposal == null` as no proposal and handles only proposal kinds the legacy path supports.
- Update fixtures without widening the new shared public contract.
- Verify the shared package and legacy mobile typecheck/tests with the repository dependency links.

### 2. Make typed-message durability atomic and dismissal-safe

- Add regressions for repeated identical text, a crash/failure between draft and turn persistence, and Close before/after the durable-message callback.
- Persist the pending turn and its user message in one storage transaction before coaching begins.
- Recover legacy text drafts only when body and original creation timestamp identify the same message; never select an arbitrary historical duplicate.
- Track whether the processing message is durable. Ignore Close while a typed message is still being checkpointed; allow Close after durability is confirmed.
- Keep the composer cleared once the message is accepted.

### 3. Reconcile schema-v6 partial assistant responses without duplication

- Add a migration-compatibility test where the assistant message exists but schema-v7 companion rows do not.
- Make response persistence idempotent: insert a missing message, or verify an identical existing message, then create missing metadata/source/proposal rows in the same transaction.
- Reject a conflicting existing message instead of overwriting or duplicating it.

### 4. Preserve and validate proposal provenance atomically

- Add failing tests for memory proposals with multiple `sourceMessageIds`, invalid sources, and tombstoned sources.
- Carry proposal source IDs into memory-source records and commit the accepted memory plus all provenance rows in one transaction.
- Validate every proposed and support source against a visible, non-tombstoned conversation message before mutation. Mark invalid proposals stale/unsupported and reject invalid support links without partial writes.

### 5. Isolate response-action failures from the composer

- Add regressions for feedback save/remove and proposal accept/dismiss failures while the reply composer is idle or contains input.
- Add response-scoped action state keyed by response/proposal, with retry for the failed action itself.
- Keep the composer, typed text, recording state, and coaching retry context unchanged when a response action fails.
- Reload the canonical response after success or rollback so optimistic UI cannot drift from storage.

### 6. Complete the Product audit and RTL repair

- Implement the approved design-system additions first, with token/contract tests and documentation.
- Replace raw colors, geometry, typography, and motion in `ConversationActivityIndicator`, `InlineRecoveryAlert`, and the empty state with the shared roles above.
- Make maximum-width user bubbles trailing-relative: right in LTR and left in RTL. Add layout-direction contract tests.
- Preserve existing accessibility labels, Central Icons, 44pt+ hit areas, and Reduce Motion behavior.

### 7. Reconcile durable documentation and verify the candidate

- Update `docs/data-model.md` to schema v7 and document `assistant_response_metadata`, `assistant_response_sources`, `assistant_proposals`, `response_feedback`, and `preference_profiles`.
- During repair, run focused red/green suites after each task and one fast native gate after a cohesive batch, plus affected shared/backend/legacy checks and branch-topology verification.
- Commit the exact repair candidate, sign and over-install that same revision without replacing device data, prove the launched revision, and request only the named broken interaction: a typed or recorded reply becomes durable and reaches either a coaching response or its durable retry state across close/reopen.
- If that interaction fails, return to diagnosis and repeat focused checks, the fast native gate, and exact over-install. Do not run the full native matrix merely to make another attempt.
- Only after the named interaction passes: freeze that exact candidate, run `npm run verify:native-apple:all` once, run the remaining affected cross-stack checks and fresh code review, and stop for Baah's Ship decision. After Ship and merge, synchronize the shipped `main` revision one way into canonical preview and run the agent-owned smoke checks.

## Verification matrix

- Focused Swift unit/storage/view-contract tests for each repaired failure.
- `npm` shared build/typecheck and affected legacy mobile tests/typecheck.
- `npm run verify:native-apple:fast` before the repair-candidate over-install.
- One named physical interaction on the exact installed repair candidate.
- `npm run verify:native-apple:all` once, only after physical proof and on the unchanged candidate.
- `scripts/verify-branch-topology.sh build --main-ref origin/main --preview-ref origin/preview/taisa`.
- Fresh Standard + Product code review with zero Critical/Important findings.
- Exact-SHA simulator/accessibility smoke check before any device retest.

## Approval gate

Production edits start only after Baah approves this repair plan and the four backward-compatible Apple design-system additions listed above.
