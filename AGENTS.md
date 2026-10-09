# Taisa Agent Operating Instructions

## Mandatory startup

At the start of every scoped delivery cycle:

1. Read `docs/workflow.md` and `.agents/skills/taisa-workflow/SKILL.md` completely.
2. Read `docs/project-memory.md`, then inspect only the accepted decisions, reusable learnings, and canonical domain documents relevant to the task.
3. Query the Taisa Linear project, milestones, active issues, dependencies, blockers, Scope/Plan evidence, and approvals.
4. Inspect the current branch, working tree, worktrees, remote tracking, relevant contracts, verification evidence, preview revision, and active delivery chats.
5. Reconcile contradictions before modifying product code.
6. State the work tier, Linear issue/milestone, current stage, branch, blocker, next action, and next Baah approval gate.
7. Invoke the Superpowers process skill required by the Taisa orchestrator.

Within a stable cycle, re-read only state whose issue, approval, dependency, branch/worktree,
PR, CI, preview, or remote revision changed. Do not repeat global orientation merely because
a new turn or bounded Goal run began.

Read-only questions require orientation but do not create branches or workflow artifacts.

Bias toward activation: when a request is ambiguous but plausibly asks for a Taisa change,
investigation, design, process improvement, or delivery action, run lightweight workflow
orientation and infer the lightest fitting tier. Missing workflow keywords never turns an
actionable request into a future-only direction. Every actionable task requires a
non-duplicate Linear issue before work; activation does not bypass approval gates.

## Authority and gates

Linear is the sole live authority. It owns roadmap, task intake, priority, ownership, stage,
dependencies, blockers, Scope, Plan, acceptance, discussion, and gate evidence.
`docs/workflow.md` and the Taisa orchestrator define how work is performed; Git owns
versioned technical truth. Quick and ordinary Standard work uses one explicit kickoff bundle
to approve Scope and Plan together. Full or high-risk work uses separate Scope and Plan
approval. Baah retains physical-device judgment and Ship.
The agent owns routine Linear, Git, GitHub, verification, and code-coupled documentation
housekeeping within those approvals.

One delivery cycle has one primary Linear issue and one accountable conductor. Platform,
Product, and Integration remain exclusive internal work slices under that conductor, not
separate persistent Goals. Product work still uses the design-handoff process for UI design
and implementation readiness.

After approval, use `.agents/skills/taisa-workflow/templates/bounded-goal.md` for one BUILD,
REPAIR, or SHIP run. A Goal completes at its named terminal outcome and never stays active
solely to wait for Baah or unchanged CI, device, or service state. It never selects successor
work or infers approval.

One Baah defect observation enters `REPAIR_QUARANTINE`. The agent owns reproduction,
diagnosis, fix, verification, exact preview publication, and smoke testing before one focused
retest. Until the repair-release gate passes, the issue is `Unfixed; blocking; unshippable`.
Do not use Baah as a repeated exploratory tester.

If Linear is unavailable, continue only already-approved work supported by trusted recent
Scope/Plan context and Git evidence. Do not start or advance work, change a blocker, or claim
approval until Linear is available and reconciled.

Clear Ship approval authorizes the verified pull-request merge and safe deletion of the merged local and remote work branch. It does not authorize force-pushes, history rewrites, deletion of unmerged work, or removal of unrelated worktrees.

## Safety

Preserve user changes. Never develop directly on `main`. Never delete a branch until its commits are accounted for in canonical `main`. Stop and report dirty worktrees, unique commits, failed checks, conflicts, unexpected pull-request bases, or unverifiable remote state.

## Product and architecture constraints

Taisa is a personal AI career companion. Users capture daily work by voice; the native
product turns it into evidence-grounded coaching, wins, challenges, actions, and CV-worthy
moments. The shipping direction is a SwiftUI iPhone/iPad product; React Native remains a
legacy migration source until its required behavior and unique work are accounted for.

- Preserve SwiftUI and the iOS/iPadOS 26+ deployment target.
- Keep readable personal data encrypted and device-authoritative.
- Preserve the current v1 identity boundary unless an approved Scope changes it: the device
  UUID is the user identifier. Do not add application auth middleware by accident.
- The legacy backend remains Node/Express with SQLite and no migration framework. Schema
  changes require an approved migration path and matching durable documentation.
- Do not run `npx expo run:ios` or `npx expo eject` without explicit approval; use
  `npx expo start` for the legacy application. Install `mobile/` dependencies from `mobile/`;
  root workspaces are `backend` and `shared` only.
- New or rebuilt legacy UI uses NativeWind and the documented design system; do not add
  `StyleSheet.create()` to new or rebuilt components.
- Do not confuse the legacy one-shot journal analyser with the unimplemented four-mode Senior
  Self experience: Mirror, Nudge, Challenge, and Direct.

Read `docs/project-memory.md` to route to the narrowest relevant domain source. Common
commands are `npm run backend`, `npm run mobile`, and `npm run verify:native-apple:all`.

`CLAUDE.md` is a compatibility pointer for consumers that discover that filename. It must not
carry an independently editable copy of these instructions.
