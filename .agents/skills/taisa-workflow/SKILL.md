---
name: taisa-workflow
description: Thin Taisa adapter. Use for Taisa work to reconcile Linear authority, Git evidence, and conditional safety rules before selecting a Matt engineering route.
---

# Taisa workflow adapter

Matt's engineering skills own discovery, specification, tickets, implementation, review, and
retrospective steps. This adapter adds only Taisa authority, safety, and release boundaries.

Project: `31b0d99c-6f74-4c9c-af2a-12e6e25aabe0`
Team: `e95356d8-17f7-4700-bdfe-222782bea546`

## Start

1. Read the primary Linear issue, its direct blockers, approval evidence, and latest stable
   checkpoint. Linear is the sole live authority for work state.
2. Inspect the owning branch, worktree, remote relation, exact commit, and relevant verification
   evidence. Git owns versioned technical truth.
3. Read `docs/project-memory.md`, then only the domain source it names for this work.
4. Reconcile contradictions before mutation. If Linear is unavailable, continue only work already
   authorized by readable recent evidence. Do not start work or advance a gate.
5. Select one Matt route from the precedence in `AGENTS.md`. Do not reproduce that route here.

Every actionable task needs a non-duplicate Linear issue. Read-only orientation inside an existing
issue is the exception. Preserve dirty worktrees and user changes. Never develop on `main`.

## Authority adapter

Baah owns product intent, materially different experiences, security, privacy, destructive data,
paid services, difficult-to-reverse choices, every reviewable tracer experience, physical or
perceptual QA, and Ship. A tracer with no reviewable product experience requires a non-empty reason
instead of invented approval. The agent owns ordinary technical plans, tickets, branches,
implementation, tests, review, verification, pull requests, and delivery mechanics inside those
decisions.

Record only decisions and stable delivery checkpoints in Linear. Use native blocker and parent
relations. Do not narrate commands, polling, unchanged waits, or repeated evidence.

## Conditional adapters

- Linear operations: read `docs/agents/issue-tracker.md`.
- Product UI: read `docs/design-system.md` and use `design-handoff`. Inventory shared components,
  semantic styles and tokens, and Central Icons before Product code. An unavailable item stops
  Product work until Baah approves its exact shared-system treatment in Linear.
- Preview, QA, repair, or Ship: read the applicable section of `docs/workflow.md`. It is the single
  detailed authority for candidate freeze, browser simulator review, canonical Preview,
  `REPAIR_QUARANTINE`, physical QA, topology, merge, and cleanup.
- Branch topology: run `scripts/verify-branch-topology.sh` in the mode named by
  `docs/workflow.md`.
- Bounded BUILD, REPAIR, or SHIP run: fill
  `.agents/skills/taisa-workflow/templates/bounded-goal.md`; the template points back to the
  authoritative workflow instead of copying it.
- Delivery waste or closeout: use Matt's `retro`. Small reversible improvements are agent-owned.
  Changes to authority, privacy, security, verification coverage, Preview, meaningful cost, or
  Ship stop for Baah.

## Stable Taisa invariants

- Every pull request links one Linear tracer, declares one reviewable outcome, and declares all
  applicable additive risks. Repository rules can raise risk but cannot lower approved Linear
  classification. Unknown or uncertain sensitive changes fail closed for review.
- Pull requests use fast and focused checks selected by risk. Release candidates require the
  complete applicable matrix on the exact candidate revision. Exact-revision evidence remains
  reusable while code, dependencies, toolchain, signing, configuration, and covered inputs remain
  unchanged.
- Readable personal data stays encrypted and device-authoritative.
- The device UUID remains the v1 user identifier unless approved product intent changes it.
- SwiftUI and iOS/iPadOS 26+ remain the shipping direction. React Native is migration evidence.
- Do not run `npx expo run:ios` or `npx expo eject` without explicit approval.
- The legacy backend remains Node/Express with SQLite and no migration framework.
- New legacy UI uses NativeWind, not `StyleSheet.create()`.
- Never confuse the legacy analyser with Mirror, Nudge, Challenge, and Direct.
- Clear Ship approval permits the verified merge and safe accounted cleanup only. It never permits
  a force-push, history rewrite, deletion of unmerged work, or unrelated cleanup.

## Completion

Run the checks named by the owning ticket and `docs/workflow.md`. Product work also needs the
pre-merge design-system audit and browser simulator evidence. A completion or Ship claim must use
`superpowers:verification-before-completion`. Use `superpowers:finishing-a-development-branch`
only after the applicable review and verification gates pass.

At Closeout, record the outcome, deviations, exact evidence, remaining debt, and next gate in
Linear. Promote a learning to Git only when it is a reusable technical contract or decision.
