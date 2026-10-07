# Linear Roadmap Authority Design

**Status:** Draft — revised after Baah feedback; awaiting renewed review
**Last updated:** 2026-10-07
**Track:** Workflow
**Tier:** Full

## Purpose

Make Linear the operating system for all actionable Taisa work, regardless of whether Baah or an agent performs it. Linear owns roadmap sequencing, milestones, task intake, scope, plans, active work, status, ownership, dependencies, blockers, discussion, and acceptance. Keep only code-adjacent information in the repository when it must version atomically with the implementation: operating constraints, architecture and public contracts, durable decisions, data migrations, and verification evidence.

The change removes manual status duplication across Linear, `docs/roadmap.md`, the Active Work table in `docs/workflow.md`, and new feature-specific scope/plan files. Existing historical artifacts are preserved until their useful content is migrated or explicitly accounted for; this workflow change does not mass-delete them.

## Authority model

| Information | Authoritative system | Repository representation |
|---|---|---|
| Product direction and milestone sequence | Linear project and milestones | No repository roadmap copy |
| Task intake, active stage, owner, dependency, blocker, and priority | Linear issues | Queried during workflow orientation; not copied into a manual table |
| Scope and acceptance criteria | Linear issue description or attached Linear document | No independently maintained repository copy; durable constraints move to the appropriate canonical contract or decision record |
| Feature design and implementation plan | Linear issue/document plus sub-issues or checklist | No independently maintained repository copy; code-adjacent architectural contracts remain in repository canonical docs |
| Durable architecture and technical decisions | Repository architecture/contract docs and decision records | Linked from Linear |
| Verification and device-QA evidence | Commits, repository evidence records when needed, and Linear updates | Exact revision and outcome summarized in Linear |
| Branch, pull request, and merge identity | Git and GitHub | Linked or commented on the Linear issue |
| Historical roadmap/status changes | Linear activity and project updates | No duplicate repository changelog |

If Linear is temporarily unavailable, agents may continue an already-approved issue only when its current scope and plan are available in recent trusted context and Git evidence. They must not start a new actionable task, infer a stage transition, or claim a changed blocker until Linear can be read and reconciled.

## Universal issue policy

Every actionable task gets a Linear issue before work begins, whether Baah or an agent will perform it. This includes features, bugs, investigations, design work, planning, documentation, workflow changes, reviews, releases, chores, and repository cleanup.

Exceptions are limited to:

- read-only questions or status reports that create no deliverable or external mutation;
- orientation needed to identify the correct existing issue; and
- individual commands, tests, or implementation steps that belong inside an already active issue.

Before creating an issue, search exact and semantic matches across active and archived Linear work. Continue the existing issue when the requested outcome is the same. Create a sub-issue only when the work has an independently reviewable outcome, distinct owner, distinct dependency, or separate approval/acceptance boundary. Otherwise use the parent issue's checklist, comments, and status updates.

When Baah asks an agent to perform new actionable work in chat, the agent searches for or creates the issue before Scope, planning, investigation, or implementation begins. Work Baah performs personally also lives in Linear; Baah may create it directly, or the agent creates/updates it when asked. The issue's assignee represents the accountable human owner; agent execution is recorded through the issue activity, linked chat/task, delegate field when supported, and evidence comments rather than invented human identities.

## Linear structure

Use the existing Linear project `Taisa` (`31b0d99c-6f74-4c9c-af2a-12e6e25aabe0`) and team `A Playing Field` (`e95356d8-17f7-4700-bdfe-222782bea546`). Do not create a duplicate project.

### Milestones

1. **Native foundations** — shipped native app foundation plus encrypted local storage and recovery.
2. **Functional native product** — production Home foundation, Chats/history, goals/actions/evidence, profile/settings/privacy, and recovery UI.
3. **Combined Home and Insights** — weekly work, continuity, grounded lead insight, nested Insights history, proposal review, notifications, and governed actions.
4. **Voice and Senior Self** — reliable native audio/transcription/coaching streaming plus the four coaching modes and bounded memory/context.
5. **Visual refinement and platform integration** — mature native design system, responsive hierarchy, motion, materials, resources, notifications, and approved platform capabilities.
6. **Release cutover** — regression and migration QA, native release approval, React Native retirement, and safe repository cleanup.

Milestones express strategic order. They do not authorize Scope, Plan, Build, external infrastructure, release, or deletion.

### Issues

Create an issue at task intake. Scope, design, plan, implementation, review, and Ship advance within that same issue. Creating the issue authorizes no work beyond orientation; the existing Baah approval gates still control Scope, Plan, and Ship.

Immediately reconcile these approved active slices:

- **SwiftUI Home foundation** — In Progress; Platform + Product; branch `codex/swiftui-home-scope`; link its scope, design handoff, specification, and implementation plan; record canonical-preview and device-QA exit requirements.
- **Swift native audio and conversation streaming** (`APF-30`) — In Progress; Platform + Product; replace the stale written-spec-review gate with its current Build blocker: unexpected physical recording termination and Send/transcription reliability; retain the existing scope and architecture documents.

Represent future direction through milestones. Create a task issue only when Baah or an agent is actually taking responsibility for scoping, investigating, planning, or executing that outcome; leave purely prospective ideas in the milestone description until then.

### Legacy issues

Preserve completed historical issues. For open React Native implementation issues whose intended outcome is replaced by the native roadmap:

- set the issue to Canceled;
- add a concise explanation that the framework-specific implementation is superseded by the Swift-native roadmap;
- link the relevant native milestone or active issue when one exists; and
- retain the issue history rather than deleting or rewriting it.

`APF-28` (React Native persistent input bar and Chat UI) and `APF-29` (React Native RecordingGlow) meet this rule. `APF-27` is already Done and remains historical evidence.

## Combined Home and Insights continuity

The smaller SwiftUI Home foundation is not the complete Home vision and does not supersede the existing Combined Home and Insights planning. Linear must preserve a named **Combined Home and Insights** milestone whose description includes:

- `This Week` planning and deliberate carry-over;
- `Keep Moving` continuity across projects, blockers, decisions, and follow-ups;
- a consolidated proposal-review count;
- one confirmed, grounded lead insight with inspectable evidence;
- a nested Insights destination for current, superseded, and historical insights;
- local attention and notification behavior;
- `What Taisa can handle` capability governance;
- separation of observations, recommendations, and accepted tasks; and
- no AI or network request merely because Home opens.

The existing React Native-oriented scope and plans remain source material. They must be reconciled to Swift storage, concurrency, navigation, accessibility, preview, and signed-device architecture before a new implementation issue enters Build. Material changes return to Scope and Plan approval.

## Repository changes

### `docs/roadmap.md`

Remove `docs/roadmap.md`. Update every repository reference to direct agents and humans to the Taisa Linear project. Durable product principles that materially constrain implementation move to the appropriate canonical product, architecture, design-system, or decision document rather than surviving as a second roadmap.

### `docs/workflow.md`

Remove the Active Work table and replace it with a session-orientation contract:

1. read the Taisa Linear project, milestones, and active scoped issues;
2. inspect the current branch, worktrees, remote tracking, scope, plan, and verification evidence;
3. reconcile contradictions before modifying product code;
4. treat Linear approval records, Scope, Plan, stage, and blockers as authoritative while repository contracts and decisions remain authoritative for versioned technical truth; and
5. follow the offline fallback when Linear is unavailable.

Update document conventions, freshness rules, gate actions, parked-work rules, and housekeeping responsibilities so they do not instruct agents to maintain duplicate status tables or create new feature-specific scope and plan files by default.

### `.claude/skills/taisa-workflow/SKILL.md`

Update the orchestrator with the same authority split. Keep its existing approval gates, preview authority, Git safety, Product/Platform tracks, design-system rules, and translation rules. Remove instructions to update a repository Active Work table. Require duplicate prevention before creating Linear issues and exact issue reconciliation at every gate.

Replace the current Quick-tier exception: Quick work also receives a Linear issue, but it may use a compact issue description and checklist instead of separate Scope/Plan documents. Standard and Full work store their Scope, design, plan, acceptance, and approval evidence in the issue or attached Linear documents.

### `AGENTS.md` and `CLAUDE.md`

Update startup and continuity guidance to query Linear for live roadmap state while reading repository artifacts for durable decisions. Preserve the requirement to inspect Git/worktrees and stop on dirty or unaccounted work.

Remove instructions that assume new feature scope and plan files are the default workflow output. Retain repository documentation only for information that must travel atomically with code or remain available to builds, tests, migrations, operations, and offline recovery.

### Verification tooling

Update `scripts/verify-workflow.sh` and relevant documentation-freshness checks so they validate the new authority model rather than requiring a local Active Work table. Verification must detect:

- repository instructions that still call `docs/roadmap.md` or an Active Work table the live status authority;
- repository instructions that still require new feature scope/plan files for ordinary work;
- missing Linear project/team identifiers in the orchestrator;
- contradictory gate ownership; and
- broken links between documented repository artifacts.

The verifier must not require network access or make Linear mutations.

## Session behavior

At the start of a scoped task, the agent reports:

- tier;
- current stage from Linear, cross-checked against repository evidence;
- branch/worktree;
- blocker or dependency;
- next Baah approval gate; and
- whether Linear was unavailable or contradictory.

If Linear and repository evidence disagree:

- approved Scope, Plan, acceptance, and gate evidence remains controlled by Linear;
- versioned architecture, public contracts, durable decisions, migrations, and verification evidence remain controlled by the repository;
- live stage and blocker remain controlled by Linear only when the referenced artifacts and Git state support that stage;
- the agent stops advancement, identifies the contradiction, and repairs the stale side within existing authority;
- missing approval evidence cannot be invented from a Linear status; and
- a repository plan marked Draft cannot enter Build merely because a Linear issue says In Progress.

## Migration procedure

1. Inspect the existing Taisa Linear project, milestones, issues, and statuses before creating anything.
2. Create this workflow migration's own Linear issue and attach/link the approved design and subsequent execution evidence.
3. Add or reconcile the six milestones without duplicating equivalent existing milestones.
4. Create the missing SwiftUI Home foundation issue and migrate its approved scope, design, plan, and acceptance evidence into Linear.
5. Update `APF-30` to the current Build state and physical-device blocker.
6. Cancel `APF-28` and `APF-29` as framework-specific work superseded by the native roadmap, preserving their histories.
7. Publish one Linear project status update explaining the authority migration and active native work.
8. Update repository workflow artifacts and validators in one branch, including removal of `docs/roadmap.md` and its references.
9. Verify the repository changes locally and read back the affected Linear entities.
10. Preserve historical scope/plan files during this migration unless their content is explicitly migrated and their removal is independently reviewed; do not remove legacy branches or worktrees.

## Acceptance criteria

- Linear is explicitly the sole live authority for roadmap sequence, milestones, active stages, priorities, ownership, dependencies, and blockers.
- The repository remains authoritative only for operating constraints, architecture and public contracts, durable decisions, migrations, verification and QA evidence, and Git evidence that must version with the code.
- Linear remains authoritative for approved Scope, design intent, implementation Plan, acceptance, and gate evidence; those records are not recreated as independently maintained repository documents.
- `docs/roadmap.md` is removed and no repository instruction depends on it.
- `docs/workflow.md`, the Taisa orchestrator, `AGENTS.md`, and `CLAUDE.md` consistently apply the authority split and offline fallback.
- Every actionable task, including Quick work, design, investigation, planning, documentation, review, and work performed by Baah, has an issue-intake rule before execution.
- New Standard and Full work stores scope, design, plan, approval, and acceptance evidence in Linear rather than creating feature-specific repository documents by default.
- Repository verification passes without network access and rejects reintroduction of duplicate live-status authority.
- The Linear project contains the six reconciled milestones without duplicates.
- SwiftUI Home foundation has an In Progress issue linked to its approved repository artifacts.
- `APF-30` reflects its actual Build state and current device blocker.
- `APF-28` and `APF-29` are canceled as superseded React Native implementation work, with explanatory comments or descriptions.
- Combined Home and Insights remains visible as a named milestone with its grounded-insight and weekly-work contract preserved.
- Creating an issue for unscoped work does not imply authorization; its state and content make the current gate explicit.
- Existing dirty worktrees, uncommitted files, branches, and migration reference history are unchanged.

## Out of scope

- Changing approved Product behavior or implementing any Product slice.
- Approving Combined Home and Insights for Swift Build.
- Merging, deleting, or rewriting branches, worktrees, or Git history.
- Creating paid services, Apple capabilities, deployment infrastructure, or releases.
- Deleting historical repository scope and plan files before their useful content and references are migrated or explicitly accounted for.
- Introducing a bidirectional automatic synchronization service between Git and Linear.
