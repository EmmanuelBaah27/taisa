# Taisa Agent Operating Instructions

## Matt-first engineering router

Linear is the sole live authority for roadmap, task intake, priority, ownership, stage,
dependencies, blockers, Scope, acceptance, discussion, and gate evidence. Git owns versioned
technical truth. Every actionable task needs a non-duplicate Linear issue before work begins.
If Linear is unavailable, continue only already-approved work supported by trusted recent
context and Git evidence; do not start or advance work, change a blocker, or claim approval.

After lightweight Linear, branch/worktree, dependency, and relevant-domain orientation, choose
exactly one primary Matt route in this precedence order:

1. A hard bug or performance regression routes to `diagnosing-bugs`, even when the repair may
   fit in one focused session.
2. A foggy or stalled effort routes to `wayfinder` before implementation.
3. Repo feature or change discovery routes to `grill-with-docs` so decisions become durable
   evidence rather than a conversational checklist.
4. Approved work that fits in one focused session routes to `implement`.
5. Approved multi-session work routes to `to-spec`, then `to-tickets`, then per-ticket
   `implement`. Tickets are vertical tracer slices with native Linear blocker relationships;
   each tracer contains its creative and functional loops, TDD, Standards review, Spec review,
   focused verification, and a meaningful cumulative Preview checkpoint.
6. Delivery closeout and process waste route to `retro`. Apply small reversible improvements
   autonomously; return material authority, safety, Preview, cost, or Ship changes to Baah.

Ordinary technical Plan approval is not a Baah gate. Baah decides product intent, priorities,
exclusions, materially different or difficult-to-reverse experience choices, security,
privacy, destructive-data and paid-service choices, tracer experience reviews, physical and
perceptual QA, and Ship. The agent owns specification, tracer decomposition, blockers,
branches and worktrees, routine product and engineering judgment, tests, review, verification,
pull requests, and delivery mechanics within those decisions.

## Taisa safety invariants

- Preserve user changes. Never develop directly on `main`. Stop on dirty worktrees, unique
  commits, failed checks, conflicts, unexpected pull-request bases, or unverifiable remote
  state. Never delete a branch until its commits are accounted for in canonical `main`.
- Keep readable personal data encrypted and device-authoritative. Preserve the current v1
  identity boundary unless approved Scope changes it: the device UUID is the user identifier;
  do not add application authentication middleware accidentally.
- Every Product build is design-system-first. Inventory each component, style, token, and icon
  from Central Icons before Product implementation. Every authored visual style must use an existing semantic
  design-system token or component. A missing semantic role is a DS gap:
  stop before Product or screen code, tell Baah the affected surfaces and recommendation, and
  record Baah's approval in Linear before the exact shared-system addition or narrow exception
  proceeds. At code review and before merge approval, audit Product work already built. Replace every eligible
  feature-local presentation with the available design-system contract. If an
  item is unavailable, tell Baah which surface is affected and keep the gate closed.
- Preserve SwiftUI and iOS/iPadOS 26+ as the shipping direction. React Native is a legacy
  migration source. Never run `npx expo run:ios` or `npx expo eject` without explicit approval.
- The legacy backend remains Node/Express with SQLite and no migration framework; schema
  changes need an approved migration path. Install `mobile/` dependencies from `mobile/`;
  root workspaces are `backend` and `shared`. Rebuilt legacy UI uses NativeWind, never new
  `StyleSheet.create()`. Do not confuse the legacy analyser with the unimplemented four-mode
  Senior Self experience: Mirror, Nudge, Challenge, and Direct.
- Clear Ship approval authorizes only the verified pull-request merge and safe deletion of the
  merged work branch. It never authorizes force-pushes, history rewrites, deletion of unmerged
  work, or removal of unrelated worktrees.

## Conditional Taisa extensions

Load only the adapter triggered by the work:

- Linear operation and evidence: `docs/agents/issue-tracker.md`.
- Domain, privacy, data, identity, and architecture: `docs/project-memory.md`, then only the
  relevant canonical documents it routes to.
- Product UI: `docs/design-system.md` plus `design-handoff`.
- Canonical Preview, QA, repair quarantine, and Ship: the applicable sections of
  `docs/workflow.md` and `.agents/skills/taisa-workflow/SKILL.md` until thin adapters replace
  the legacy source. These sources retain safety contracts but do not restore ordinary Plan
  approval or override the Matt-first route.
- Triage classification only: `docs/agents/triage-labels.md`.

A Taisa extension must name the unmet need, use the smallest mechanism, and state when it can
be removed. During APF-80's expand phase, the legacy workflow remains reachable for retained
safety contracts. APF-86 removes its duplicated process only after the tracer workflow is
proven.

`CLAUDE.md` is a compatibility pointer for consumers that discover that filename. It must not
carry an independently editable copy of these instructions.
