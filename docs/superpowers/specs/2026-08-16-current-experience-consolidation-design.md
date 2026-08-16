# Current Experience Consolidation Design

**Date:** 2026-08-16
**Status:** Approved in brainstorming; awaiting written-spec review
**Tier:** Full
**Track:** Platform + Product
**Authors:** Baah + Codex

## Outcome

Taisa has one maintained development line that opens into the current app experience. The local-first platform, Chats surfaces, chat input states, and current design-system work coexist on that line. Screen-by-screen design work continues there, so a developer or device tester cannot accidentally launch the legacy build by using the documented runtime.

The design system is a foundation layer within the current Product branch, not an independent long-lived source of truth. `main` remains the only permanent branch and becomes authoritative after verified Ship approval.

## Current-state finding

All major work lines share `3dcdcf6` (`main`) as their relevant divergence point, but they do not form one safe linear stack:

- `feature/local-first-coaching-platform` contains the newest platform foundation and extensive mobile runtime changes.
- `feature/chats` contains the Chats list, thread route, presentation utilities, and UI primitives.
- `feature/chat-input-states` is a direct descendant of `feature/chats` and adds the input state machine, voice/text composer behavior, recorder coordination, and related backend changes.
- `feature/design-system-evolution` points at `main` and contains extensive uncommitted documentation, token, Storybook, font, configuration, and component changes.
- `docs/reimagine-product-scope` is documentation-oriented and has unrelated uncommitted mobile dependency changes. It must not be used as the runtime baseline.

A direct merge of `feature/chat-input-states` into the platform branch is unsafe because the branch-to-branch diff presents many platform files as deletions. Consolidation must port intent in bounded slices and resolve each overlapping file against the local-first architecture.

## Branch and worktree model

After the implementation plan is approved, create one typed integration branch from the verified head of `feature/local-first-coaching-platform`. The plan will choose the final branch name, with `feature/current-experience` as the default.

That branch receives all reconciliation work and becomes the documented mobile runtime for device QA and subsequent screen builds. Existing branches and worktrees remain unchanged as recovery sources until the integration branch is merged into `main` and commit ancestry or patch equivalence is verified.

No work is developed directly on `main`. No branch is deleted merely because its changes appear to have been copied.

## Reconciliation sequence

### 1. Freeze and inventory

Capture for every worktree:

- branch, HEAD, upstream, and merge base;
- clean or dirty status;
- unique commits;
- untracked files;
- a patch or recoverable commit for every uncommitted change;
- ownership classification: Platform, Product screen, design system, documentation, tooling, or generated dependency state.

The inventory is a verification artifact. Any unexplained deletion, unique commit, or dirty file stops cleanup but does not prevent read-only analysis.

### 2. Establish the platform baseline

Use `feature/local-first-coaching-platform` as the candidate base because it owns the architecture needed by the current product: local data authority, conversation repositories, navigation helpers, coaching context, privacy controls, and their tests.

First run its applicable verification from its own worktree. Failures are recorded and resolved on the integration branch; the source branch remains intact.

### 3. Port Chats by responsibility

Port the Chats work as small coherent slices rather than merging its branch wholesale:

1. presentation tests and date/preview utilities;
2. `ChatListRow` and `ThreadMessage` UI primitives plus documentation;
3. Chats list route behavior;
4. thread presentation and navigation;
5. loading, empty, error, and accessibility states.

Where the platform branch already has a newer repository, route helper, session model, or voice composer, adapt the Chats UI to that interface. Do not replace newer platform code with older branch versions.

### 4. Port chat input states

Reconcile the input state machine and its tests separately from backend and recorder changes. For each slice, compare the behavior with the local-first voice composer and streaming transcription implementation. Preserve whichever implementation satisfies the latest approved product contract and has stronger lifecycle guarantees; combine behavior only when tests define a coherent single owner.

Overlapping recorder, transcription, store, API, and database files require semantic reconciliation. A merge result that compiles but restores server-authoritative or legacy journaling behavior is a failure.

### 5. Absorb design-system evolution

Before changing the design-system worktree, make its uncommitted state recoverable. Classify each change:

- tokens and typography;
- reusable UI components and variants;
- Storybook configuration and stories;
- font and asset changes;
- tooling/configuration;
- workflow and documentation.

Port accepted changes onto the integration branch before screen changes that depend on them. Components remain typed, presentational, NativeWind-based, and documented. Screens consume primitives from `mobile/src/components/ui/`; they do not establish competing tokens or inline primitive styles.

If a design-system change alters every existing usage or breaks an API, show Baah the visual before/after and affected screens before applying it.

### 6. Make the current experience the runtime

Update developer documentation so the maintained integration worktree is the explicit source for `npm run mobile`. Confirm the app's initial route and tab shell lead to the current Taisa surfaces. Legacy screens may remain temporarily for migration safety, but they must not be the default navigation path or the experience seen during ordinary launch.

No environment-dependent redirect or undocumented choice of worktree may determine whether the old or current app appears.

## Chats-to-thread transition boundary

The expanding-card interaction is a follow-on Product slice built only after consolidation verification.

The Chats row is the visual transition source; `/thread/[id]` remains the authoritative destination. On activation, a transition coordinator captures the selected row's measured bounds and visible presentation, animates a temporary visual shell toward the viewport, and navigates to the thread while preserving the conversation identifier. The list does not become responsible for message fetching or thread state.

The reverse transition may collapse toward the source row only when that row is mounted and measurable. Otherwise Back uses a normal route transition. Reduced-motion mode uses a short crossfade. Data loading, navigation errors, and interrupted gestures must never leave a blocking overlay mounted.

The exact motion curve, duration, transformed content, and reverse gesture remain part of the dedicated Figma handoff for the thread screen; they are not guessed during consolidation.

## Ownership boundaries

- **Platform:** local persistence, repositories, context assembly, coaching contracts, privacy, transcription services.
- **Feature logic:** chat input state machine, transition coordinator, presentation utilities.
- **Routes/screens:** fetching, navigation, layout, scroll ownership, and selection state.
- **Design system:** tokens, typography, icons, reusable presentational rows, messages, controls, and motion-safe visual shells.
- **Documentation:** canonical runtime instructions, Active Work, design-system reference, and reconciliation evidence.

Each behavior has one owner. Screens do not duplicate recorder or transition state machines; design-system components do not fetch data or navigate; platform modules do not encode screen layout.

## Verification and gates

Consolidation is complete only when:

1. repository workflow verification passes;
2. backend tests and TypeScript build pass;
3. shared checks pass;
4. mobile TypeScript and relevant Jest suites pass;
5. Storybook covers newly accepted design-system states where infrastructure exists;
6. DS compliance passes;
7. a clean install/launch from the documented worktree opens the current experience;
8. Chats can open and resume a conversation using the local-first data path;
9. Baah completes device QA;
10. final review finds no unexplained lost commits, files, tests, or capabilities.

The Plan gate authorizes reconciliation work. The Ship gate authorizes the verified merge to `main` and only then the safe removal of fully accounted-for work branches and disposable worktrees.

## Failure and recovery

- A conflict is resolved by product and architecture intent, never by accepting one whole side automatically.
- A failed verification keeps the integration branch in Build and leaves source branches intact.
- An unaccounted unique commit or uncommitted file blocks cleanup.
- If the local-first baseline itself cannot pass verification, fix or explicitly rescope it before importing Product work.
- If a design-system change cannot be traced to an intended visual outcome, preserve its patch and defer it rather than silently shipping or discarding it.

## Deliberate exclusions

This effort does not redesign unrelated screens, add platform capabilities, rewrite the app in SwiftUI, introduce a second permanent integration branch, or implement the expanding-card motion before its thread design handoff is confirmed.
