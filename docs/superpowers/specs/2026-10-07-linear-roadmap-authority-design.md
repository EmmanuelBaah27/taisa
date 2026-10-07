# Linear Roadmap Authority Design

**Status:** Draft — awaiting Baah review  
**Last updated:** 2026-10-07  
**Track:** Workflow  
**Tier:** Full

## Purpose

Make Linear the single live authority for Taisa roadmap sequencing, milestones, active work, status, ownership, dependencies, and blockers. Keep the repository authoritative for durable product and engineering evidence: approved scope, architecture, implementation plans, decisions, migration records, verification, and QA.

The change removes manual status duplication across Linear, `docs/roadmap.md`, and the Active Work table in `docs/workflow.md`. It does not move product specifications or source-controlled evidence into Linear-only storage.

## Authority model

| Information | Authoritative system | Repository representation |
|---|---|---|
| Product direction and milestone sequence | Linear project and milestones | Short pointer and durable principles in `docs/roadmap.md` |
| Active stage, owner, dependency, blocker, and priority | Linear issues | Queried during workflow orientation; not copied into a manual table |
| Scope and acceptance criteria | Repository scope document | Linked from its Linear issue after Scope approval |
| Architecture and design decisions | Repository specs and decision records | Linked from Linear |
| Implementation plan | Repository plan document | Linked from Linear after Plan approval |
| Verification and device-QA evidence | Repository records and commits | Summarized and linked from Linear |
| Branch, pull request, and merge identity | Git and GitHub | Linked or commented on the Linear issue |
| Historical roadmap/status changes | Linear activity and project updates | No duplicate repository changelog |

If Linear is temporarily unavailable, agents may continue already approved work from repository artifacts and Git evidence. They must not infer a new stage transition, create a new active slice, or claim a changed blocker until Linear can be read and reconciled.

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

Create or update issues only when a slice has approved Scope, consistent with Taisa's gates.

Immediately reconcile these approved active slices:

- **SwiftUI Home foundation** — In Progress; Platform + Product; branch `codex/swiftui-home-scope`; link its scope, design handoff, specification, and implementation plan; record canonical-preview and device-QA exit requirements.
- **Swift native audio and conversation streaming** (`APF-30`) — In Progress; Platform + Product; replace the stale written-spec-review gate with its current Build blocker: unexpected physical recording termination and Send/transcription reliability; retain the existing scope and architecture documents.

Do not create implementation issues yet for Current Work, Grounded Insights, proposal governance, Chats/history, Goals, Profile/settings, Senior Self, visual refinement, or cutover unless their Scope is approved. Represent their intended order through milestones and the project's durable description.

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

Replace the manually maintained status matrix with a compact document that:

- declares Linear as the live roadmap authority;
- links to the Taisa Linear project;
- records only durable product direction and ordering principles;
- explains which information remains authoritative in the repository;
- documents the offline fallback; and
- contains no copied active statuses, blockers, owners, or due dates.

### `docs/workflow.md`

Remove the Active Work table and replace it with a session-orientation contract:

1. read the Taisa Linear project, milestones, and active scoped issues;
2. inspect the current branch, worktrees, remote tracking, scope, plan, and verification evidence;
3. reconcile contradictions before modifying product code;
4. treat repository scope/plan evidence as authoritative for approved content and Linear as authoritative for live stage and blockers; and
5. follow the offline fallback when Linear is unavailable.

Update document conventions, freshness rules, gate actions, parked-work rules, and housekeeping responsibilities so they do not instruct agents to maintain duplicate status tables.

### `.claude/skills/taisa-workflow/SKILL.md`

Update the orchestrator with the same authority split. Keep its existing approval gates, preview authority, Git safety, Product/Platform tracks, design-system rules, and translation rules. Remove instructions to update a repository Active Work table. Require duplicate prevention before creating Linear issues and exact issue reconciliation at every gate.

### `AGENTS.md` and `CLAUDE.md`

Update startup and continuity guidance to query Linear for live roadmap state while reading repository artifacts for durable decisions. Preserve the requirement to inspect Git/worktrees and stop on dirty or unaccounted work.

### Verification tooling

Update `scripts/verify-workflow.sh` and relevant documentation-freshness checks so they validate the new authority model rather than requiring a local Active Work table. Verification must detect:

- repository instructions that still call `docs/roadmap.md` or an Active Work table the live status authority;
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

- approved artifact content remains controlled by the repository;
- live stage and blocker remain controlled by Linear only when the referenced artifacts and Git state support that stage;
- the agent stops advancement, identifies the contradiction, and repairs the stale side within existing authority;
- missing approval evidence cannot be invented from a Linear status; and
- a repository plan marked Draft cannot enter Build merely because a Linear issue says In Progress.

## Migration procedure

1. Inspect the existing Taisa Linear project, milestones, issues, and statuses before creating anything.
2. Add or reconcile the six milestones without duplicating equivalent existing milestones.
3. Create the missing SwiftUI Home foundation issue and link its approved artifacts.
4. Update `APF-30` to the current Build state and physical-device blocker.
5. Cancel `APF-28` and `APF-29` as framework-specific work superseded by the native roadmap, preserving their histories.
6. Publish one Linear project status update explaining the authority migration and active native work.
7. Update repository workflow artifacts and validators in one branch.
8. Verify the repository changes locally and read back the affected Linear entities.
9. Do not remove legacy branches or worktrees as part of this workflow-authority change.

## Acceptance criteria

- Linear is explicitly the sole live authority for roadmap sequence, milestones, active stages, priorities, ownership, dependencies, and blockers.
- The repository remains authoritative for approved scope, architecture, plans, decisions, verification, QA, and Git evidence.
- `docs/roadmap.md` contains no manually copied live status table.
- `docs/workflow.md`, the Taisa orchestrator, `AGENTS.md`, and `CLAUDE.md` consistently apply the authority split and offline fallback.
- Repository verification passes without network access and rejects reintroduction of duplicate live-status authority.
- The Linear project contains the six reconciled milestones without duplicates.
- SwiftUI Home foundation has an In Progress issue linked to its approved repository artifacts.
- `APF-30` reflects its actual Build state and current device blocker.
- `APF-28` and `APF-29` are canceled as superseded React Native implementation work, with explanatory comments or descriptions.
- Combined Home and Insights remains visible as a named milestone with its grounded-insight and weekly-work contract preserved.
- No unscoped future slice is represented as an authorized implementation issue.
- Existing dirty worktrees, uncommitted files, branches, and migration reference history are unchanged.

## Out of scope

- Changing approved Product behavior or implementing any Product slice.
- Approving Combined Home and Insights for Swift Build.
- Merging, deleting, or rewriting branches, worktrees, or Git history.
- Creating paid services, Apple capabilities, deployment infrastructure, or releases.
- Moving complete repository specs and plans into Linear-only documents.
- Introducing a bidirectional automatic synchronization service between Git and Linear.
