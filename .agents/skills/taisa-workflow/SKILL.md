---
name: taisa-workflow
description: Use at the start of every Taisa change, investigation, plan, build, review, or Ship task to reconcile Linear live delivery state with Git technical evidence and route the required process skill.
---

# Taisa Workflow Orchestrator

Linear is the sole live authority. It owns Taisa roadmap milestones, actionable task intake,
priority, ownership, stage, dependencies, blockers, Scope, Plan, acceptance, discussion, and
gate evidence. Git is authoritative for source, operating constraints, architecture/public
contracts, durable decisions, migrations, and verification evidence that must version with
code.

Project: `31b0d99c-6f74-4c9c-af2a-12e6e25aabe0`
Team: `e95356d8-17f7-4700-bdfe-222782bea546`

## 1. Mandatory session start

Read completely:

- `AGENTS.md`
- `docs/workflow.md`
- `docs/project-memory.md`
- this skill

Then:

1. Query the Taisa Linear project, milestones, active issues, relations, blockers,
   priorities, recent updates, Scope/Plan documents, and approval evidence.
2. Run `git status --short --branch`, `git worktree list --porcelain`, `git branch -avv`,
   `git fetch --prune origin`, and inspect relevant commits, PRs, tests, preview revision,
   and active delivery chats.
3. Reconcile contradictions before product or workflow mutation.
4. State tier, issue/milestone, stage, branch/worktree, blocker/dependency, next action,
   next Baah gate, and Linear availability.

Preserve dirty worktrees and user changes. Never develop on `main`.

### Linear unavailable / offline fallback

If Linear is unavailable, continue only already-approved work supported by recent trusted
Scope/Plan context and Git evidence. Do not create a new task, infer a transition, change a
blocker, or claim approval. Reconcile Linear before the next stage or gate.

### Contradictions

Linear controls live delivery truth and approvals; Git controls versioned technical truth.
A status never substitutes for approval. A Draft technical artifact cannot enter Build
because an issue says In Progress. Stop advancement, identify and repair the stale side,
then re-read both.

## 2. Universal issue intake

Every actionable task requires a Linear issue before investigation, design, planning,
implementation, documentation, review, release work, chores, or work Baah performs.
Read-only questions and commands within an existing issue are exceptions.

Before creating anything:

- search exact and semantic matches, including archived work;
- continue an issue when the intended outcome matches;
- use a sub-issue only for an independently reviewable outcome, owner, dependency, or gate;
- otherwise use checklist/comments;
- keep purely prospective direction in a milestone description until someone owns action.

Issue creation is intake, not authorization.

## 3. Activation and tier

Default toward activation for a concrete change, investigation, design, scope, plan, fix,
review, validation, delivery, or process improvement. Pure status/read-only questions receive
orientation and an answer only. Explicit future-only ideas go to the relevant milestone.

| Tier | Treatment |
|---|---|
| Quick | Compact issue with intent, acceptance, checks, and gate. |
| Standard | Inline Work Map + Discussion Map; separate Scope and Plan evidence in Linear. |
| Full | Full track decomposition, Linear documents/sub-issues as useful, every gate. |

## 4. Work Map and Discussion Map

Standard/Full work begins with a Linear-linked Work Map: slices, Platform/Product/Integration
owner, outcome, dependency, approval, `XS / S / M / L / XL`, pickup order, parallel work,
critical path, counters, and an evidence-based pace estimate.

Show a Discussion Map before the first substantive question:

- **Platform discussion:** outcome, current system, ownership/persistence, behavior, Product
  contract, privacy/security, failure/recovery, dependencies, validation.
- **Product discussion:** outcome, journey/priorities, states, interaction, accessibility,
  Platform capability, device-QA expectations. Layout belongs after Scope.
- **Integration discussion:** compatibility, end-to-end flow, cross-track states/failures,
  preview strategy, combined verification, release readiness.

Diagrams use layman meaning plus technical truth, real component/service/store labels, plain
language arrows, and visible ownership, trust, storage, failure, and offline boundaries.

## 5. Stages and automatic skill routing

`ORIENT → DISCUSS → SCOPE → PLAN → BUILD → REVIEW + QA`

| Event | Required skill |
|---|---|
| New behavior/workflow design | `superpowers:brainstorming` |
| Approved multi-step specification | `superpowers:writing-plans` |
| Bug/unexpected behavior | `superpowers:systematic-debugging` |
| Feature/bug implementation | `superpowers:test-driven-development` where practical |
| Approved Plan execution | `superpowers:executing-plans` |
| Build complete | `superpowers:requesting-code-review` |
| Completion/Ship claim | `superpowers:verification-before-completion` |
| Integration/cleanup | `superpowers:finishing-a-development-branch` |

Use subagents only when Baah explicitly authorizes them and work is independent.

### Scope

Store outcome, why now, observable acceptance, dependencies, architecture, open questions,
and exclusions in the Linear issue/document. Baah approves material Scope.

### Product design between Scope and Plan

After Product Scope approval, invoke `design-handoff` for Figma/screenshots, sketch, or an
approved Visual Companion result. Record layout intent, key states, components/tokens,
interactions, accessibility, and device-QA evidence in Linear. Material differences return
to Scope.

### Plan

Store tasks, tests, interfaces, dependencies, integration, verification, and Product DS
inventory in Linear. Present a plain-language summary; Baah approves Plan. Material build-path
changes return to Plan.

### Build

After Plan approval, set In Progress and execute continuously. Platform and independent
Product foundation may run in parallel; Integration waits for both sides. Use TDD and record
exact commits/checks after each material step.

### Review + QA

Use requesting-code-review and verification-before-completion. Resolve blockers, publish the
exact verified mobile revision to canonical preview, record QA, prepare a PR to `main`, and
stop at Ship.

## 6. Approval gates

| Gate | Required evidence | Baah signal |
|---|---|---|
| Scope | Linear Scope with acceptance/exclusions/dependencies | approval intent |
| Plan | Linear Plan with tasks/tests/integration | approval intent |
| Ship | review, verification, PR, applicable device QA | explicit Ship intent |

Never treat silence, issue status, or previous-stage approval as the next gate.

## 7. Preview feedback preflight

Assume Baah’s mobile/UI feedback comes from `preview/taisa`.

1. Read preview commit and dirty state.
2. Confirm remote plus served/signed runtime revision.
3. Confirm the component/behavior and architecture match the implementation worktree.
4. If not, stop, reconcile/port, verify, republish, and only then interpret feedback.

Never request device QA until the exact verified commit is integrated, pushed, and confirmed
served or installed. Repeat for every QA revision.

## 8. Product, DS, AI, and data constraints

- Native Product targets iOS/iPadOS 26+ and prefers native SwiftUI/platform behavior.
- Production UI uses real encrypted local data; ordinary browsing triggers no AI/network.
- Cover loading, empty, content, stale/offline, failure/recovery, disabled/permission, and
  accessibility states where relevant.
- Support Dynamic Type, VoiceOver, increased contrast, Reduce Motion/transparency, safe areas,
  keyboard use, and touch targets.
- Keep business logic outside presentation and add shared DS only when reuse is proven.
- Product DS order: shared typed presentation first, screens/data/navigation second.
- Backward-compatible DS variants are autonomous; global behavior and breaking changes need
  Baah confirmation with affected usages.
- Phone-authoritative personal data; deliberate bounded AI requests; provenance; explicit
  facts/interpretations/recommendations/proposals/accepted work; no silent AI mutation.
- Paid/irreversible retries are idempotent; logs contain no private content or credentials;
  failures, timeouts, partial streams, relaunch, conflicts, and recovery are tested.

## 9. Verification matrix

| Area | Checks |
|---|---|
| Backend | Jest + TypeScript build |
| Shared | type-check/build + affected backend tests |
| React Native | TypeScript + relevant tests; UI also DS/Storybook/device QA |
| Native Apple | applicable package tests, project/contracts/DS verification, builds, device QA |
| Cross-stack | all affected layers |
| Docs/workflow | link/path consistency, workflow verifier, applicable freshness, clean diff |

Missing infrastructure is a gap, never a pass.

## 10. Linear lifecycle

Status IDs:

- Todo: `8092f145-a7b5-4e09-812e-1d3212fc1c7d`
- In Progress: `ad545d06-1ef1-4c5d-86c7-44e1e3724409`
- Done: `b2c07c6b-bf80-40d1-8e08-9c941b04f137`
- Canceled: `e2a4cb1f-daf0-4269-8acc-9b0fed9224f5`

After every material step, comment exact branch/commit/PR/preview revision, checks/result,
risk/blocker, next action, and next Baah gate. Relations hold dependencies. Project updates
hold milestone-level health.

QA failure creates/updates one non-duplicate issue per distinct outcome with preview revision,
reproduction, severity, acceptance, and relation. Release blockers return the feature to
Build; fixes repeat verification and preview publication.

Parking cancels with reason and preserves branch/worktree/artifacts/history.

Linear error: retry issue creation once, record the failure, and continue only already-
approved work with readable Scope and Plan.

### Deferred capabilities

An explicit deferral is captured in one matching non-duplicate Linear Backlog issue, never a
repository backlog. Search exact and semantic matches first. Record origin/reason, user value
and reconsideration trigger, dependencies/unknowns, architectural guardrails, durable Git and
Linear evidence, and dated history. Lifecycle is **Captured → Watching → Candidate → Planned → Shipped or Dropped**.
Candidate is recommendation only; Planned requires Baah-approved
Scope and Plan; Shipped requires canonical-main evidence; Dropped requires Baah's explicit
decision or documented supersession.

Before Scope/Plan, consult related deferrals. At Review/Ship, read them back and reconcile
lifecycle against implementation, canonical preview, verification, device evidence, and
`main`. Linear controls live lifecycle; Git controls versioned technical truth. Failed Linear
access uses the visible offline fallback and must be caught up before a stage or gate.

Named voice deferrals: hands-free turn-taking; simultaneous playback and capture; interruption detection
and barge-in; full-duplex conversational voice; and live transcription before Send.
Current audio contracts must not assume capture and playback
can never coexist, but these records do not authorize implementation.

Monthly reconciliation runs the first Monday at 09:00 Africa/Accra as a thread heartbeat. It
checks Linear against durable Git contracts, reports access failures, and stays quiet when
there is no meaningful change. It may record safe routine evidence but never approves Scope, Plan, priority changes, lifecycle promotion into active work, or Ship.

## 11. Documentation, Closeout, and memory

Repository docs exist only for code-adjacent constraints/contracts/decisions/migrations and
immutable verification evidence. Historical scopes/specs/plans/QA records remain history,
not live authority. New repository feature Scope/Plan documents are not the default.

At Review, record **Closeout** in Linear: actual outcome, deviations, decisions/learnings,
exact evidence, debt/risk, canonical docs changed, next gate, and any deferred-capability
lifecycle changes. Before Ship, read back related deferrals and verify lifecycle against
actual implementation and merge evidence. Perform a
**memory-promotion check**; promote reusable findings only to `docs/learnings.md`, a durable
decision, or the narrow canonical contract they improve.

Canonical documentation authority: proposed code-coupled docs live on the owning work branch;
`main` becomes canonical after merge; preview is never documentation authority. A material
change returns to Scope/Plan. Mark retained obsolete docs `Status: Superseded` with
`Superseded by: <Linear URL, path, or merge SHA>`.

## 12. Git and Ship

`main` is the only permanent shipping branch. `preview/taisa` is integration-only and never
a PR base. Use `<type>/<short-kebab-case-description>`, isolated worktrees, conventional
commits, and squash merge by default.

Clear Ship approval authorizes: re-fetch/reconcile; full verification/review/device evidence;
push; PR to `main`; squash merge; verify local/remote/PR SHA agreement; delete only the
accounted merged branch/worktree; prune; update Linear with merge SHA and Closeout.

Stop on dirty state, failed checks, conflicts, unexpected base, unique commits, unverifiable
remote state, or another worktree owning the branch. Ship never authorizes force-push,
history rewrite, unmerged-work deletion, or unrelated-worktree cleanup.

## 13. BTS and translation

Use `> **BTS:**` for non-obvious architecture, Platform enablement, DS enforcement, root-cause
bug fixes, API data flow, or DS breaking changes. Keep it to 1–3 skippable lines.

Translate Platform work into what it enables for the UI, Plans into plain-language outcomes,
and DS changes into visible before/after behavior. Do not make Baah choose routine engineering
details already inside approved Scope and Plan.
