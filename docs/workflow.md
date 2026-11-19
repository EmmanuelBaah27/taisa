# Taisa Release Safety Workflow

**Status:** Active
**Last updated:** 2026-11-19

This is the single detailed authority for candidate freeze, browser simulator review,
canonical Preview, `REPAIR_QUARANTINE`, QA readiness, topology, Ship, and safe cleanup.
`AGENTS.md` owns route selection, the Taisa skill owns startup and conditional loading, and
[`docs/agents/issue-tracker.md`](agents/issue-tracker.md) owns Linear operations.

## Platform, Product, and Integration vocabulary

Platform, Product, and Integration are discussion lenses, never ticket owners or persistent
tracks. Vertical tracers and native Linear blockers own delivery structure. `AGENTS.md` owns
Matt route selection, and the applicable Matt skill owns discovery, specification, tickets,
implementation, review, and retrospective mechanics.

## Review and release safety

### Review + QA

Invoke `requesting-code-review` and `verification-before-completion`. Resolve blocking
findings. Record exact checks, revisions, PR, preview, device observations, remaining risk,
and approval state in Linear.

The following sequence is the authoritative **candidate-freeze contract** for every final QA
or release gate. Other workflow surfaces reference this contract; they do not redefine it.

1. Confirm verification readiness before spending the gate: required dependencies, runtimes,
   signing, simulators/devices, and standard repository links or generated inputs are present.
2. Complete implementation and the smallest applicable focused checks.
3. Run a fresh whole-candidate review before the complete matrix. Resolve every blocking
   finding with focused checks, then review the resulting candidate again.
4. Freeze the clean candidate revision. For a release or final repair-release gate, run the
   complete applicable matrix once on that exact revision. Other pull requests keep their fast,
   focused, risk-selected exact-revision evidence instead.
5. Preserve that exact-revision evidence through PR and Ship while code, dependencies,
   toolchain, signing, configuration, and covered inputs remain unchanged. Any change to one
   of those invalidators reopens only the affected proof, plus review when candidate content
   changed; it does not justify repeating unaffected checks.
6. For device-facing work, integrate the verified candidate into canonical preview and prove
   topology, exact ancestry/revision, and the affected interaction with focused build/smoke
   checks. Repeat the complete matrix only when preview integration changes candidate content
   or an invalidator above, not for a clean one-way merge of already-verified commits.

The complete matrix never substitutes for review, and a review that can still change the
candidate never follows the complete matrix.

For Product changes, review evidence also includes the pre-merge DS audit, replacements made
with available DS contracts and Central Icons, and the complete list of remaining unavailable
items or approved exceptions. Missing evidence or an available-but-unused DS contract blocks
Ship approval.

### Browser simulator review

Every reviewable native Product tracer and final native Product candidate must pass agent-owned
browser simulator review. Use the Build iOS Apps `ios-simulator-browser` skill with an explicit
Simulator UDID. Start a `serve-sim` helper scoped to that UDID, open its printed URL in the Codex
in-app browser, and prove that the page renders a live simulator frame. A loaded page, a running
helper, or a connection status without a rendered frame is not evidence. Keep the helper alive
while review continues. On exit, clean up only the helper for that explicit UDID.

Review the affected interaction and relevant accessibility state in the live frame. Record the
exact candidate revision, simulator model, OS version, affected interaction, accessibility
checks, and a browser-visible screenshot. If a native change has no visible or interactive
Product effect, record the browser review as inapplicable with the reason.

Browser simulator review does not replace physical-device, hardware-specific, or perceptual
judgment owned by Baah. It is the agent gate before Baah QA, not evidence that physical QA
passed.

### Verification economy

Every pull request links one Linear tracer, declares one reviewable outcome, and declares all
applicable additive risks. Repository classification can raise risk but cannot lower approved
Linear classification. Unknown or uncertain sensitive changes fail closed for review.

Pull requests use fast and focused checks selected from logic, UI, network, device, data,
security, and workflow risks. Device-sensitive changes require exact-revision physical QA
evidence when the affected behavior cannot be proven in the simulator. Release candidates
require the complete applicable matrix on the exact candidate revision. Exact-revision evidence
remains reusable while code, dependencies, toolchain, signing, configuration, and covered inputs
remain unchanged.

The risk-to-proof contract is:

| Risk | Required automated proof | Additional evidence |
| --- | --- | --- |
| Logic | Contract tests, package tests, and one Personal app compile | None |
| UI | Logic proof plus design-system checks and one Preview compile | Browser simulator review when visible |
| Network | Contract tests, affected backend tests, package tests, and one Personal app compile | Focused failure and retry review |
| Device | Logic proof plus one generic device compile | Exact-revision physical QA |
| Data | Storage, migration, recovery, affected backend tests, and package tests plus one Personal app compile | Recovery or migration evidence when affected |
| Security | Security contracts, affected backend tests, and package tests plus one Personal app compile | Baah approval for material security changes |
| Workflow | Workflow contracts and candidate-safe policy checks | Protected-base classification |
| Release | Complete matrix and Release build | Final physical QA and Ship approval |

During calibration, the protected-base policy reports contract mismatches while the existing
safety gate remains required. After five historical backtests and three live pull requests show
no missed required risk and no unnecessary full run, change the protected-base policy to strict
enforcement and reconcile branch protection. Until then, do not claim strict enforcement is live.

Use the smallest applicable verification that can falsify the current change first, then
expand only after focused checks pass or the risk boundary requires it. Reuse fresh evidence
when code, dependencies, toolchain, signing, configuration, and covered inputs are unchanged
for the exact covered revision; do not rerun an
identical expensive command merely to produce another transcript. Run independent checks concurrently
when they do not share mutable state. The complete release matrix remains mandatory at a
release or final repair-release gate. During repair quarantine, do
not spend the complete matrix before the named broken interaction is proven fixed.

Before an expensive gate, run a readiness preflight that can fail cheaply. For long-running
commands, use an event-capable wait or the longest practical bounded wait that still meets the
needed response window. Poll only when output can materially change the next decision; unchanged
running state produces no new reasoning turn, transcript, Linear comment, or user update.

Autonomous repair remains outcome-based, not attempt-based. Do not repeat the same failed
approach or unchanged verification. After three materially distinct unsuccessful approaches
without new diagnostic evidence, record `UNRESOLVED_ESCALATION` with the root blocker and
smallest Baah-controlled decision; otherwise continue the repair loop until it is proven.
Unchanged CI, device, or service waits produce no narration or repeated reasoning turns.

| Change area | Required checks |
|---|---|
| Backend | Backend Jest suite + backend TypeScript build |
| Shared types | Shared type-check/build + affected backend tests |
| React Native logic | Mobile TypeScript check + relevant tests |
| React Native UI | Mobile TypeScript, DS compliance, Storybook checks, device QA |
| Native Apple | Applicable package tests, project/contracts/DS verification, target builds, device QA |
| Cross-stack | All affected backend/shared/client checks |
| Docs/workflow | Link/path consistency, workflow verifier, freshness where applicable, clean diff |

Missing infrastructure is a reported gap, never a passing test.

### Initial QA-readiness gate

Before the first Baah QA request, all applicable requirements must pass:

1. Acceptance criteria map to concrete evidence.
2. Narrow and complete applicable verification layers pass on the candidate revision.
3. Blocking review findings are resolved.
4. Required vertical tracers and their cross-cutting acceptance constraints are complete.
5. Device-facing work is committed, integrated, and pushed to canonical preview.
6. The served or installed build is confirmed as that exact revision.
7. Every visible or interactive native Product change has passed browser simulator review with
   a live-frame screenshot and the required revision, simulator, interaction, and accessibility
   evidence.
8. Known limitations and inapplicable checks are explicit and do not contradict acceptance.
9. Linear records the candidate revision, evidence, remaining risk, and exact requested
   observation.

Failure of an applicable item returns to autonomous Build; it never produces partial QA.
Automated/simulator evidence covers every supported configuration in the verification matrix.
Physical QA is requested only for hardware or perceptual judgment that automation cannot
establish. One final interaction may contain separated iPhone/iPad checks without becoming
multiple exploratory rounds.

### One-observation repair quarantine

One Baah defect observation is sufficient. Record the exact preview/build revision and enter
`REPAIR_QUARANTINE`; do not ask Baah to repeat, reconfirm, characterize, or periodically
retest the same defect while engineering evidence is incomplete.

Use the bounded physical **repair candidate** lane when agent-owned evidence cannot prove a
previously recorded device-only or perceptual failure. Before installing a candidate, require:
authority/revision confirmation; a stable reproduction, diagnostic trace, or explicit contract
assertion; a supported root cause; failing-before and passing-after evidence where technically
possible; the fix; focused regression checks; the fast native gate; and the existing branch
topology gate proving a clean, `main`-based work branch with no preview-only ancestry.

Sign that exact commit with the existing bundle identifier and install it over the current app
without uninstalling, resetting, or discarding device data. Terminate any running app process
before launch, then prove the launched process reports the exact installed revision; merely
reactivating a process that survived the over-install is stale evidence. The repair candidate is not canonical.
It is not `QA_READY`, Ship-ready, shippable, or merge-ready. It authorizes only one named broken interaction.
Exploratory or general QA is prohibited. If that interaction fails, record the new evidence,
remain in `REPAIR_QUARANTINE`, and repeat diagnose → fix → focused regression →
fast native → exact over-install; do not run the full native matrix merely to attempt again.

After the named interaction passes, freeze that exact candidate and run a fresh whole-candidate
code review before the expensive final matrix. Resolve every blocking finding with the smallest
applicable checks. Any code, dependency, toolchain, signing, configuration, or covered-input
change after physical proof invalidates the proof and returns to the candidate loop; review must run again on
the resulting candidate. Once review is clean and the physical proof still applies to that exact
unchanged revision, run the full native matrix once. Then obtain Ship approval, merge to `main`,
synchronize one-way into canonical preview, confirm the served/installed revision, and perform
the agent smoke check. Every final repair-release item must be recorded as passed or explicitly
inapplicable with evidence; silently skipping an item keeps the issue in `REPAIR_QUARANTINE`.

The authoritative sequence is:

`Baah observation → REPAIR_QUARANTINE → repair Goal → diagnose/fix → focused + fast verification → exact repair candidate over-install → one named broken interaction → fresh whole-candidate review → resolve blockers and re-prove if changed → full matrix once on the reviewed, proven, unchanged candidate → Ship → merge → canonical preview`.

If the repair cannot be proven, the issue remains **Unfixed; blocking; unshippable**. It is
not QA-ready, Ship-ready, complete, deferred, or eligible for successor work. Baah receives
only one of two material notifications: `fixed and proven` with one focused retest, or
`still unfixed and genuinely blocked` with evidence, materially different approaches tried,
the recommended redesign/reversion/deferral/capability, consequences, and one smallest
Baah-controlled decision or action.

## Canonical preview and feedback authority

Local worktree previews are non-canonical. Only a reviewed integration-branch checkpoint can
publish to the cumulative canonical Preview. Publication is additive and must preserve every
existing included candidate. A broken or obsolete candidate must be explicitly reverted or replaced.
Record the exact Preview, spec, and tracer revisions for each publication.

A clean integration checkpoint needs topology proof, a build, and an affected-interaction smoke
check. Reuse the tracer's unchanged exact-revision evidence and do not repeat unaffected broad
verification. Preview-only history cannot enter a feature branch, spec branch, or `main`.

This extension exists because Baah needs one stable cumulative product while several branches move
independently. When main can provide the same stable cumulative product without bypassing QA or
Ship, the canonical Preview extension can be removed.

Baah’s UI/mobile feedback is assumed to come from canonical `preview/taisa`. Before using it
as evidence:

1. Read preview worktree commit and dirty state.
2. Confirm `origin/preview/taisa` and the served/signed runtime revision.
3. Confirm the component and behavior exist there with the same architecture as the owning
   implementation worktree.
4. If any check differs, stop, reconcile/port, verify, republish, and only then request QA.

Never ask Baah to test a mobile change until its exact verified commit is integrated into
`preview/taisa`, pushed, and confirmed as the revision served or installed, except for the
bounded repair-candidate lane above. That exception is deliberately noncanonical and can test
only the previously recorded broken interaction before final verification and publication.

## Product and design-system quality

- Cover loading, empty, populated, stale, offline, failure, recovery, disabled, permission,
  and accessibility states where relevant.
- Prefer native SwiftUI and Apple platform behavior for the native product; target iOS and
  iPadOS 26 or later.
- Use real encrypted local data in production UI; never production mocks.
- No AI/network request during ordinary local browsing unless approved behavior requires it.
- Keep business logic outside presentation components.
- Every authored visual style must use an existing semantic design-system token or
  component. Product UI must not introduce raw or arbitrary colors, typography, spacing,
  radii, shadows, materials, motion values, or one-off style variants. When no suitable role
  exists, add the semantic token or component to the design system, document its intent and
  platform mappings, and verify it before any screen consumes it. Platform-provided defaults
  and runtime values derived from accessibility, safe areas, geometry, or state are not new
  authored tokens.
- Support Dynamic Type, VoiceOver, increased contrast, Reduce Motion, reduced transparency,
  safe areas, keyboard use, and suitable touch targets.
- DS breaking changes always require Baah confirmation with affected usages; global behavior
  changes require confirmation; backward-compatible variants may proceed autonomously.

## AI and data quality

- The phone remains authoritative for readable personal data unless Baah approves otherwise.
- Send bounded content only after deliberate user action.
- Preserve provenance and distinguish confirmed facts, interpretations, recommendations,
  proposals, and user-accepted work.
- AI output never silently mutates authoritative records.
- Paid or irreversible retries are idempotent.
- Logs and diagnostics contain no private content or credentials.
- Test invalid responses, unavailable providers, timeouts, partial streams, retries,
  relaunch, conflicts, and recovery; expose uncertainty.

## QA failure and parked work

For each QA failure, create or update one non-duplicate Linear issue with observed preview
revision, reproduction, severity, acceptance criteria, ownership, and relation to the feature.
Release-blocking failure returns the feature to Build. Outside the bounded physical repair-
candidate lane, repeat the applicable verification and preview publication before renewed
device QA. Inside `REPAIR_QUARANTINE`, follow the narrower authoritative sequence above:
focused regression plus fast verification, exact over-install, one named interaction, and fresh
whole-candidate review; run the full matrix only after review is clean and that physical proof
still applies to the unchanged candidate.

Parking sets the issue Canceled with reason and preserves branches, worktrees, artifacts, and
history. Do not delete or rewrite parked work.

## Repository documentation

Keep only information that must version with code: operating/safety constraints;
architecture/public contracts; data models/migrations; API contracts; design-system
contracts used by code; durable decisions; and immutable verification/release evidence.

Historical scopes, specifications, plans, and QA records remain history, not live stage or
roadmap authority. New feature-specific repository Scope/Plan documents are not the default.

### Canonical documentation authority

The owning work branch contains proposed code-coupled documentation; `main` becomes
canonical after approval and merge. `preview/taisa` is never documentation authority.
When branches overlap an artifact, reconcile against `origin/main`, the owning branch, and
Linear before the next gate.

### Material change

A material change alters outcome, acceptance criteria, exclusions, user-visible behavior,
architecture/public contract, persistence/ownership, dependency order, security/privacy,
verification, or approval responsibility. Return to Scope or Plan. Formatting, clearer
wording, evidence links, and status metadata are non-material.

### Superseded documents

For a retained code-coupled document, set `Status: Superseded`, add
`Superseded by: <Linear URL, path, or merge SHA>`, and update active references. Preserve
history unless Baah explicitly approves deletion.

## Documentation freshness cadence

### Freshness and Closeout

Delivery closeout and repeated delivery waste route through Matt's `retro` process. A small,
reversible environment improvement is agent-owned. Mechanical failure produces a check or
automation; repeated navigation cost produces a pointer or tool; a judgment failure produces a
review standard; duplicated process is consolidated or removed. Retrospective evidence names the
resulting check, pointer, review standard, tool, process removal, or explicit no-change conclusion.
A retrospective change to authority, privacy, security, verification coverage, Preview, meaningful cost, or Ship
stops for Baah's explicit decision before implementation.

Run `scripts/verify-doc-freshness.sh` for affected repository artifacts that require Status
and Last updated metadata. At Review, perform a **Closeout** in Linear: actual outcome,
deviations, decisions/learnings, exact evidence, remaining debt, canonical docs changed,
next gate, and any deferred-capability lifecycle changes. Before Ship, read back every
related deferral and confirm that implementation, canonical preview, and merge evidence
support its recorded lifecycle. Perform the **memory-promotion check**: promote reusable evidence to
`docs/learnings.md` or a durable decision/contract only when it benefits future work.

At Ship Closeout, reconcile current Linear priorities, blockers, dependencies, and approval
readiness, then publish exactly one **Recommended next outcome**. Give the evidence-based
reason and name the next Baah gate. Rank candidates in this order:
release-blocking defect or data/security/privacy risk; dependency for an approved milestone;
missing milestone acceptance; highest user value among unblocked approved work; evidenced
reliability/accessibility/maintainability/cost improvement; cosmetic refinement. Within a
rank, prefer the outcome unlocking more downstream work, then lower delivery risk, then the
smaller independently valuable slice. State the evidence and tie-breaker. Never provide an alternatives list. When no candidate is safely actionable, publish exactly one **No next outcome recommended** result with the blocking reason and next Baah gate.

A recommendation is advisory, not authorization. Never reopen or start the successor issue.
Never create the successor branch or Goal. Never change the successor status. Never begin the successor work.
Baah explicitly approves the successor kickoff before any of those mutations or execution
may begin.

Use exactly one form: **Recommended next outcome:** `<one outcome>` — **Reason:** `<evidence>` — **Next Baah gate:** `<explicit gate>`; or **No next outcome recommended:** `<blocking condition>` — **Reason:** `<evidence>` — **Next Baah gate:** `<explicit gate>`.

## Git and shipping

### Canonical branch and naming

`main` is the only permanent branch and the only shipping branch. `preview/taisa` is a permanent integration-only
preview branch and never a PR base. Branches use `<type>/<short-kebab-case-description>` with
`feature/`, `fix/`, `chore/`, `docs/`, `refactor/`, `test/`, or `spike/` as appropriate.

Branch setup: resolve a clean isolated worktree, fetch/prune, fast-forward local `main`, branch
from `main`, then record branch ownership in Linear. Never develop on `main`.

Run the mechanical topology gate immediately after branch creation and before Build:

```bash
git fetch --prune origin
bash scripts/verify-branch-topology.sh build \
  --main-ref origin/main --preview-ref origin/preview/taisa
```

The gate rejects `main` or `preview/taisa` as a work branch, a branch missing current
`origin/main`, and any branch containing preview-only history. Do not begin implementation
until it passes.

### PR and Ship gate

Create the PR only after applicable checks pass; target `main`; link the Linear issue and
acceptance evidence. Squash merge by default. A clear Ship approval authorizes the complete
verified merge and safe cleanup transaction, but not force-pushes, history rewrites,
unmerged-work deletion, or unrelated-worktree removal.

After Ship approval:

1. Confirm clean branch/worktree and correct PR base, then run the conflict-free Ship gate:
   `bash scripts/verify-branch-topology.sh ship --pr-base main --main-ref origin/main --preview-ref origin/preview/taisa`.
2. Fetch and reconcile with `origin/main` safely.
3. Confirm the final review and risk-required verification for the exact revision. Release and
   final repair-release candidates require the complete applicable matrix. Other pull requests
   require fast and focused checks selected by their additive risks. Reuse fresh exact-revision evidence while
   code, dependencies, toolchain, signing, configuration, and covered inputs are unchanged;
   otherwise run the invalidated checks before merge.
4. Confirm required device QA and exact preview evidence.
5. Push branch and create/update the PR.
6. Squash-merge to `main`.
7. Fast-forward local `main` and verify local/remote/PR merge SHA agreement.
8. Delete only the accounted merged remote/local branch and safe disposable worktree.
9. Merge the shipped `main` revision one way into `preview/taisa`, push it, then prove the
   exact shipped revision is present with
   `bash scripts/verify-branch-topology.sh preview-sync --shipped-ref <merge-sha> --main-ref origin/main --preview-ref origin/preview/taisa`.
10. Prune refs; update Linear issue, milestone/project status, and Closeout with merge SHA.

The Ship gate uses `git merge-tree` as a non-mutating preview-integration dry run. Any
conflict stops Ship before the pull request merge; preview is never repaired by developing
on it or by rewriting shared history.

Stop cleanup on dirty state, failed checks, conflicts, unexpected base, unique commits,
unverifiable remote state, or another worktree owning the branch. Never force-delete.
