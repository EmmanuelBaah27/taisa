# Current Experience Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce one verified Taisa development line that launches the current local-first app, includes Chats and current chat input behavior, and maintains the design system inside the latest Product branch.

**Architecture:** Create `feature/current-experience` from the verified local-first platform head, then port the Chats, chat-input, and design-system work as bounded behavioral slices instead of merging branches wholesale. Preserve every source branch and dirty worktree until the integration result is on canonical `main`; make the integration worktree the documented runtime for subsequent screen work.

**Tech Stack:** Expo SDK 54, Expo Router 6, Expo Web, React Native 0.81, TypeScript 5.9, NativeWind 4, Zustand 5, React Native Reanimated 4, Expo SQLite/SQLCipher, Jest 29, Storybook React Native 10, Node/Express, Git worktrees.

**Spec:** `docs/superpowers/specs/2026-08-16-current-experience-consolidation-design.md`

**Status:** Complete — navigation correction awaiting device QA

## Global Constraints

- `main` is the only permanent branch; never develop directly on it.
- Use `feature/local-first-coaching-platform` at `edb0b3d` or its verified descendant as the integration base.
- Preserve device-local data authority, conversation repositories, context/memory logic, coaching gateway contracts, privacy boundaries, and their tests.
- Do not merge `feature/chat-input-states` wholesale: against the local-first baseline it presents current platform files as deletions.
- Preserve every unique commit, dirty file, and untracked source artifact until it is accounted for.
- Keep the existing no-auth v1 contract and Expo managed workflow.
- Use NativeWind for new UI; do not add `StyleSheet.create()` to changed UI files.
- Maintain reusable visual primitives in `mobile/src/components/ui/`, with typed exported props, stories where infrastructure exists, and `docs/design-system.md` updates.
- Use browser Storybook as the on-demand review/catalog surface. Do not add an in-app design-system route or a native Storybook gallery.
- Verify native-only gestures, haptics, safe areas, Skia, recording, and Reanimated behavior in the real Taisa screens on device.
- Keep stories and documentation publishable as a future versioned long-lived catalog, but publishing/hosting is outside this plan.
- The current runtime must launch the new experience without an environment-dependent redirect or undocumented worktree choice.
- Do not implement the Chats-to-thread expanding-card motion in this plan; it receives a dedicated Product plan after the consolidated baseline passes device QA.
- Do not delete branches or worktrees in Build. Cleanup requires verified Ship approval and proof that every source commit/file is accounted for.
- Existing uncommitted changes in `docs/reimagine-product-scope` and `feature/design-system-evolution` belong to the user and must not be overwritten.

---

## File map

### Reconciliation evidence and tooling

- Create `docs/reconciliation/current-experience-inventory.md` — immutable source-branch/worktree inventory and disposition ledger.
- Create `scripts/audit-current-experience.sh` — repeatable read-only Git audit used before integration and cleanup.
- Modify `scripts/verify-workflow.sh` only if the new reconciliation links expose an existing validation gap.

### Chats presentation on local-first data

- Create `mobile/src/utils/chatPresentation.ts` — group `LocalConversation` summaries and derive previews without depending on the legacy `Thread` store shape.
- Create `mobile/src/utils/__tests__/chatPresentation.test.ts` — deterministic local-calendar grouping and preview behavior.
- Create `mobile/src/components/ui/ChatListRow.tsx` and `ChatListRow.stories.tsx` — presentational accessible row.
- Create or reconcile `mobile/src/components/ui/ThreadMessage.tsx` and `ThreadMessage.stories.tsx` — user/assistant message presentation.
- Modify `mobile/src/components/ui/index.ts` and `docs/design-system.md` — exports and component contract.
- Modify `mobile/app/(tabs)/logs.tsx` — current Chats list backed by the local conversation repository/store.
- Modify `mobile/app/thread/[id].tsx` — current thread presentation while preserving local-first resume behavior.
- Modify `mobile/src/stores/threadStore.ts` only where an adapter is needed between local repositories and existing screen state.

### Current chat input behavior

- Create or reconcile `mobile/src/features/chat/chatInputMachine.ts`, `chatActionCoordinator.ts`, `chatSubmission.ts`, and `chatTranscription.ts` — pure behavior retained from the chat-input branch.
- Create or reconcile matching tests under `mobile/src/features/chat/__tests__/`.
- Create or reconcile `mobile/src/components/ui/ChatInputControls.tsx`, `ChatTextComposer.tsx`, `ChatTranscribingState.tsx`, and `ChatInputNotice.tsx`, with colocated stories.
- Modify `mobile/app/chat/index.tsx` — compose the reconciled UI with the local-first `VoiceComposer`, private capture, and conversation route.
- Modify `mobile/src/hooks/useVoiceRecorder.ts` and recorder/transcription services only when a failing behavioral test proves a missing lifecycle guarantee.

### Design-system evolution

- Modify `mobile/global.css`, `mobile/tailwind.config.js`, `mobile/app/_layout.tsx`, `mobile/package.json`, and `mobile/package-lock.json` — accepted Inter typography and dependency reconciliation.
- Modify `.rnstorybook` configuration and component stories — browser-accessible, development-only catalog behavior.
- Modify `docs/design-system.md` — authoritative tokens, typography, components, stories, and evolution contract.
- Preserve or remove old font assets only after all imports are migrated and repository search proves no consumer remains.

### Runtime and workflow

- Modify `SETUP.md` and `docs/v1-status.md` — identify the maintained runtime and current launch path.
- Modify `docs/workflow.md` and this plan's status — transition Scope/Plan/Build/Review state.
- Create `docs/features/current-experience-consolidation-qa.md` — device verification evidence and failures.

---

### Task 1: Freeze the source state and produce a reconciliation ledger

**Files:**
- Create: `scripts/audit-current-experience.sh`
- Create: `docs/reconciliation/current-experience-inventory.md`
- Modify: `.gitignore` only if a generated patch path would otherwise be tracked

**Interfaces:**
- Produces: a timestamped read-only audit and a ledger with one row per source branch/worktree.
- Consumed by: Tasks 2–9 and final cleanup verification.

- [ ] **Step 1: Add the read-only audit script**

```bash
#!/usr/bin/env bash
set -euo pipefail

branches=(
  main
  docs/reimagine-product-scope
  feature/local-first-coaching-platform
  feature/chats
  feature/chat-input-states
  feature/design-system-evolution
)

git status --short --branch
git worktree list --porcelain
git branch -avv
for branch in "${branches[@]}"; do
  git rev-parse "$branch"
  git merge-base main "$branch"
  git log --oneline "main..$branch"
done
```

The script prints only; it must not fetch, checkout, add, commit, stash, clean, or delete.

- [ ] **Step 2: Run the audit and verify it is non-mutating**

Run: `before=$(git status --porcelain=v1); bash scripts/audit-current-experience.sh; after=$(git status --porcelain=v1); test "$before" = "$after"`

Expected: exit 0 and identical status before/after.

- [ ] **Step 3: Write the inventory ledger**

Use this exact table shape and populate it from fresh command output:

```markdown
| Source | HEAD | Upstream | Dirty/untracked | Unique work | Disposition | Accounted by |
|---|---|---|---|---|---|---|
| `feature/local-first-coaching-platform` | `edb0b3d` | `origin/feature/local-first-coaching-platform` (ahead 12) | clean | Platform baseline | Preserve as source | — |
| `feature/chats` | `8ae6347` | none | untracked `mobile/node_modules/` only | Chats UI chain | Port by responsibility | — |
| `feature/chat-input-states` | `2a8c79f` | none | clean | Input-state descendant | Port by responsibility | — |
| `feature/design-system-evolution` | `3dcdcf6` plus working tree | `origin/main` | modified/deleted tracked DS files and untracked stories/docs/catalog files | DS working tree | Snapshot, classify, port | — |
| `docs/reimagine-product-scope` | `c27d0b8` plus working tree | none | modified `mobile/package.json` and `mobile/package-lock.json` | Approved docs + dependency edits | Preserve; docs cherry-picked later | — |
```

Refresh every value from observed data before committing. Under the table, record untracked paths and the SHA-256 checksum of a binary diff for each dirty worktree. Store patch files outside the repository in a `mktemp -d` directory; record the temporary path only for the active execution session and do not rely on it as the sole recovery mechanism.

- [ ] **Step 4: Make dirty design-system work recoverable**

From its existing worktree, create a named WIP commit containing only its current intended files after reviewing `git diff --check` and its untracked list:

```bash
git -C /Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa/.worktrees/feature-design-system-evolution add -A
git -C /Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa/.worktrees/feature-design-system-evolution commit -m "chore: preserve design system evolution work"
```

Do not include `node_modules`, credentials, generated caches, or unrelated user files. If any file's ownership is ambiguous, stop this step and present the exact path to Baah before staging.

- [ ] **Step 5: Commit the audit artifacts**

```bash
git add scripts/audit-current-experience.sh docs/reconciliation/current-experience-inventory.md
git commit -m "docs: inventory current experience branches"
```

---

### Task 2: Verify the platform baseline and create the integration worktree

**Files:**
- Modify: `docs/reconciliation/current-experience-inventory.md`
- Create at execution time: isolated worktree for `feature/current-experience`

**Interfaces:**
- Consumes: the ledger from Task 1 and `feature/local-first-coaching-platform`.
- Produces: a clean integration branch/worktree with recorded baseline verification.

- [ ] **Step 1: Invoke the required worktree process**

Read and follow `superpowers:using-git-worktrees` before creating the branch. Resolve the fresh, clean directory through that skill; do not reuse any dirty worktree.

- [ ] **Step 2: Verify the platform source in its own worktree**

Run from `/Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa/.worktrees/feature-local-first-coaching-platform`:

```bash
npm test --workspace=backend -- --runInBand
npm run build --workspace=backend
cd mobile && npm test -- --runInBand && npm run typecheck
```

Expected: every available command exits 0. The shared workspace currently has no standalone npm script; record that infrastructure gap and rely on backend/mobile TypeScript consumption until a dedicated shared check is added in a separately tested change. If another command fails, record the command and first actionable failure in the ledger, classify it as baseline debt, and do not misreport the baseline as passing.

- [ ] **Step 3: Create the integration branch from the exact verified SHA**

```bash
git worktree add /Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa/.worktrees/feature-current-experience -b feature/current-experience edb0b3d6c5b5bfdfc8903df4b9c6328f11864537
```

If the source head has advanced, substitute the freshly verified descendant SHA and record it in the ledger. Never use an unverified moving branch name as the base argument.

- [ ] **Step 4: Bring the approved consolidation docs into the integration branch**

```bash
git cherry-pick c27d0b8fd108bf90ad3d16401823c1e33b757017
```

Expected: the scope, spec, plan-era Active Work context, and no product-code changes. Resolve documentation-only conflicts by retaining both the local-first history and the new consolidation row.

- [ ] **Step 5: Update the ledger and commit baseline evidence**

Record integration path, base SHA, exact verification results, and cherry-pick SHA, then:

```bash
git add docs/reconciliation/current-experience-inventory.md
git commit -m "docs: record current experience baseline"
```

---

### Task 3: Adapt Chats presentation to local-first conversations

**Files:**
- Create: `mobile/src/utils/chatPresentation.ts`
- Create: `mobile/src/utils/__tests__/chatPresentation.test.ts`
- Modify: `mobile/src/repositories/conversationRepository.ts`
- Modify: `mobile/src/stores/threadStore.ts`

**Interfaces:**
- Consumes: `LocalConversation`, `LocalMessage`, and repository connections from the local-first platform.
- Produces: `ChatSummary`, `ChatDateGroup`, `getChatPreview(summary)`, `groupChatsByDate(summaries, now)`, and `listChatSummaries(database)`.

- [ ] **Step 1: Write failing repository/presentation tests**

Add tests proving newest-first local grouping, user-message preview preference, assistant fallback, and empty fallback:

```ts
const summaries: ChatSummary[] = [
  { id: 'older', title: 'Older', updatedAt: '2026-08-13T08:00:00Z', lastUserMessage: 'User note', lastAssistantMessage: 'Coach note' },
  { id: 'newer', title: 'Newer', updatedAt: '2026-08-13T16:00:00Z', lastUserMessage: null, lastAssistantMessage: 'Coach only' },
  { id: 'past', title: null, updatedAt: '2026-08-11T12:00:00Z', lastUserMessage: null, lastAssistantMessage: null },
];

expect(groupChatsByDate(summaries, new Date('2026-08-13T20:00:00Z')).map(group => group.label))
  .toEqual(['Today, 13 Aug 2026', 'Tue, 11 Aug 2026']);
expect(getChatPreview(summaries[0])).toBe('User note');
expect(getChatPreview(summaries[1])).toBe('Coach only');
expect(getChatPreview(summaries[2])).toBe('Open conversation');
```

The repository test inserts multiple messages and asserts that `listChatSummaries` returns one row per active conversation using the latest user and assistant messages without reading a backend API.

- [ ] **Step 2: Run tests and confirm the interfaces are missing**

Run: `cd mobile && npm test -- --runInBand src/utils/__tests__/chatPresentation.test.ts src/repositories/__tests__/conversationRepository.test.ts`

Expected: FAIL because `ChatSummary`, `groupChatsByDate`, or `listChatSummaries` does not exist.

- [ ] **Step 3: Implement the minimal local-first summary query and pure presentation functions**

Define:

```ts
export interface ChatSummary {
  id: string;
  title: string | null;
  updatedAt: string;
  lastUserMessage: string | null;
  lastAssistantMessage: string | null;
}

export interface ChatDateGroup {
  key: string;
  label: string;
  chats: ChatSummary[];
}
```

The repository query must filter archived conversations, choose the latest active message for each role, order by `conversations.updated_at DESC`, and return camel-cased fields. The pure functions must not import a Zustand store.

- [ ] **Step 4: Run focused and mobile checks**

Run: `cd mobile && npm test -- --runInBand src/utils/__tests__/chatPresentation.test.ts src/repositories/__tests__/conversationRepository.test.ts && npm run typecheck`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/src/utils mobile/src/repositories mobile/src/stores/threadStore.ts
git commit -m "feat: expose local chat summaries"
```

---

### Task 4: Port Chats list and thread UI without restoring legacy ownership

**Files:**
- Create: `mobile/src/components/ui/ChatListRow.tsx`
- Create: `mobile/src/components/ui/ChatListRow.stories.tsx`
- Create or Modify: `mobile/src/components/ui/ThreadMessage.tsx`
- Create: `mobile/src/components/ui/ThreadMessage.stories.tsx`
- Modify: `mobile/src/components/ui/index.ts`
- Modify: `mobile/app/(tabs)/logs.tsx`
- Modify: `mobile/app/thread/[id].tsx`
- Modify: `docs/design-system.md`

**Interfaces:**
- Consumes: `ChatSummary`, `groupChatsByDate`, local-first thread store/repository, and `chatConversationRoute(conversationId)`.
- Produces: accessible `ChatListRowProps` and `ThreadMessageProps`, a Chats list that opens `/thread/[id]`, and a thread whose Reply resumes the same local conversation.

- [ ] **Step 1: Add component behavior tests or Storybook interaction assertions**

Verify these contracts:

```ts
export interface ChatListRowProps {
  title: string;
  preview: string;
  needsAttention?: boolean;
  onPress(): void;
}

export interface ThreadMessageProps {
  role: 'user' | 'assistant';
  content: string;
  inputType?: 'voice' | 'text' | null;
}
```

The row is one accessible button whose label includes title and preview. User messages render as neutral right-aligned bubbles; assistant messages are unboxed. `needsAttention` defaults false and is never inferred from message text.

- [ ] **Step 2: Run the focused test/story typecheck and observe failure**

Run: `cd mobile && npm run typecheck`

Expected: FAIL while the new component contracts/exports are absent.

- [ ] **Step 3: Port the presentational components and stories**

Adapt the visual intent from commits `9d941ed` and `c031e74`, but use the integration branch's semantic tokens and icon package. Do not copy legacy store imports, router calls, raw hex values, or `StyleSheet.create()` into the UI components.

- [ ] **Step 4: Replace the Logs presentation with repository-backed Chats**

The screen must:

- display `Chats`;
- call the local summary loader on focus;
- group by local calendar date;
- render loading, empty, retained-data error, and retry states;
- navigate with `router.push({ pathname: '/thread/[id]', params: { id } })`;
- retain sufficient bottom padding for the floating voice/navigation controls.

Remove the legacy search field from the default screen because search is outside the approved Chats scope.

- [ ] **Step 5: Reconcile the thread route**

Keep local-first fetching and conversation identity. Apply the approved header/message/Reply presentation. Reply must set or route the same conversation ID through `chatConversationRoute(id)`; it must not create a new session or call a legacy `/chat/session` API.

- [ ] **Step 6: Run checks and commit**

Run: `cd mobile && npm test -- --runInBand src/utils/__tests__/chatPresentation.test.ts src/navigation/__tests__/conversationResume.test.ts && npm run typecheck`

Expected: PASS.

```bash
git add mobile/app mobile/src/components/ui mobile/src/utils docs/design-system.md
git commit -m "feat: add current Chats experience"
```

---

### Task 5: Reconcile chat input behavior with the local-first composer

**Files:**
- Create or Modify: `mobile/src/features/chat/chatInputMachine.ts`
- Create or Modify: `mobile/src/features/chat/chatActionCoordinator.ts`
- Create or Modify: `mobile/src/features/chat/chatSubmission.ts`
- Create or Modify: `mobile/src/features/chat/chatTranscription.ts`
- Create or Modify: matching files under `mobile/src/features/chat/__tests__/`
- Modify: `mobile/app/chat/index.tsx`
- Modify only if tests require: `mobile/src/hooks/useVoiceRecorder.ts`, `mobile/src/services/recorderLifecycle.ts`, `mobile/src/services/recorderOwnership.ts`, `mobile/src/services/streamingTranscription.ts`

**Interfaces:**
- Consumes: local-first `VoiceComposer`, `privateCapture`, conversation routing, and streaming transcription services.
- Produces: one pure input-state owner for idle, typing, recording, paused, transcribing, ready, submitting, and recoverable error states.

- [ ] **Step 1: Port pure behavioral tests before implementation**

Bring over the assertions from `feature/chat-input-states` commits `f7ac5a5`, `5225588`, and `bcc6fb2` for:

- typing versus recording exclusivity;
- pause/resume/discard;
- queued recorder recovery;
- transcript-ready versus transcript-error presentation;
- exactly-once submission coordination;
- conversation continuity after a reply.

Adapt fixtures to local-first conversation IDs and service interfaces; do not weaken assertions to fit current code.

- [ ] **Step 2: Run the focused tests and capture semantic conflicts**

Run: `cd mobile && npm test -- --runInBand src/features/chat src/services/__tests__/voiceComposerState.test.ts src/services/__tests__/streamingTranscription.test.ts`

Expected: imported tests fail until the state interfaces are reconciled. Record any contradictory expectations in `docs/reconciliation/current-experience-inventory.md` before choosing behavior.

- [ ] **Step 3: Implement a single pure state machine**

Retain the chat-input branch's lifecycle guarantees only where they complement the local-first composer. The state machine cannot perform navigation, repository writes, network calls, or recorder mutations; it returns state and commands. The coordinator owns command execution and uses local-first services.

- [ ] **Step 4: Recompose `mobile/app/chat/index.tsx`**

Keep local-first deliberate submission, private-save semantics, route/overlay presentation, and cached-conversation guards. Replace duplicated inline input-state branching with the reconciled machine and DS components. Do not replace the file wholesale from either source branch.

- [ ] **Step 5: Run lifecycle, route, and type checks**

Run:

```bash
cd mobile
npm test -- --runInBand src/features/chat src/services/__tests__/recorderLifecycle.test.ts src/services/__tests__/recorderOwnership.test.ts src/services/__tests__/voiceComposerState.test.ts src/navigation/__tests__/conversationResume.test.ts
npm run typecheck
```

Expected: PASS with no duplicate recorder owner and no backend-authoritative conversation write.

- [ ] **Step 6: Commit**

```bash
git add mobile/app/chat mobile/src/features/chat mobile/src/hooks mobile/src/services mobile/src/components/ui docs/reconciliation/current-experience-inventory.md
git commit -m "feat: reconcile current chat input states"
```

---

### Task 6: Absorb and verify design-system evolution

**Files:**
- Modify: `mobile/global.css`
- Modify: `mobile/tailwind.config.js`
- Modify: `mobile/app/_layout.tsx`
- Modify: `mobile/package.json`
- Modify: `mobile/package-lock.json`
- Modify: `mobile/.rnstorybook/preview.tsx` and generated/story configuration as present on the DS source
- Modify: component `*.stories.tsx` files accepted from the DS source
- Modify: `docs/design-system.md`
- Modify: `docs/reconciliation/current-experience-inventory.md`

**Interfaces:**
- Consumes: the recoverable DS source commit from Task 1 and current integration-branch components.
- Produces: one Inter-based token/typography system, an on-demand browser Storybook catalog, and a disposition entry for every DS source file.

- [ ] **Step 1: Classify every DS source path**

Compare the preserved DS commit with `main` and list each path in the ledger as `accept`, `adapt`, `defer`, or `reject`. `defer` and `reject` require a written reason; deletions of Strichpunkt font files require proof that no import remains.

- [ ] **Step 2: Add failing typography/runtime assertions**

Add a lightweight test or verification script that asserts:

- `global.css` registers `Inter_400Regular`, `Inter_500Medium`, `Inter_600SemiBold`, and `Inter_700Bold` utilities;
- `_layout.tsx` loads those four font registrations;
- `mobile/package.json` exposes `storybook:web` as `EXPO_PUBLIC_STORYBOOK=true expo start --web`;
- no `mobile/app/design-system.tsx` route or navigation item exposes the catalog inside Taisa;
- every newly exported visual module has a colocated story, excluding explicitly documented infrastructure wrappers.

- [ ] **Step 3: Run the assertions and confirm the current gap**

Run: `cd mobile && npm test -- --runInBand && npm run typecheck`

Expected: the new assertions fail before accepted DS files are ported.

- [ ] **Step 4: Port accepted tokens, fonts, stories, and browser catalog configuration**

Use the local-first package versions as dependency floors. Add only missing packages required for Storybook to render through Expo Web; never downgrade Expo, React Native, Reanimated, SQLite, SecureStore, or test infrastructure to match the DS source worktree. Add `"storybook:web": "EXPO_PUBLIC_STORYBOOK=true expo start --web"`, keep Storybook excluded from the ordinary app entry path, and do not port `mobile/app/design-system.tsx`. Run `npm install` only inside `mobile/` so the lockfile reflects the reconciled manifest.

- [ ] **Step 5: Audit design-system compliance**

Run:

```bash
rg -n 'StyleSheet\.create|#[0-9A-Fa-f]{3,8}' mobile/app/'(tabs)'/logs.tsx mobile/app/thread/'[id]'.tsx mobile/src/components/ui/ChatListRow.tsx mobile/src/components/ui/ThreadMessage.tsx
rg -n 'StrichpunktSans' mobile docs/design-system.md
test ! -e mobile/app/design-system.tsx
cd mobile && npm test -- --runInBand && npm run typecheck
```

Expected: no new `StyleSheet.create()`, no raw hex in the reconciled screen/UI files, no remaining Strichpunkt consumer after approved removal, no in-app catalog route, and tests/typecheck pass. Start `npm run storybook:web` separately and verify the catalog renders in a browser before stopping the development server.

- [ ] **Step 6: Commit**

```bash
git add mobile docs/design-system.md docs/reconciliation/current-experience-inventory.md
git commit -m "feat(ds): consolidate current design system"
```

---

### Task 7: Make the current experience the documented default runtime

**Files:**
- Modify: `mobile/app/_layout.tsx`
- Modify: `mobile/app/(tabs)/_layout.tsx`
- Modify: `SETUP.md`
- Modify: `docs/v1-status.md`
- Create: `docs/features/current-experience-consolidation-qa.md`

**Interfaces:**
- Consumes: consolidated navigation, Chats, chat route, and design system.
- Produces: deterministic initial navigation and a single documented worktree/start command.

- [ ] **Step 1: Add or extend route tests**

Assert that a normal initialized profile enters the current tab shell, the history destination is labelled Chats, opening a chat retains its conversation ID, and no ordinary launch path targets the legacy journaling/Logs presentation.

- [ ] **Step 2: Run route tests and verify the old default is exposed**

Run: `cd mobile && npm test -- --runInBand src/navigation`

Expected: FAIL until labels/default routing/documentation are reconciled.

- [ ] **Step 3: Reconcile launch and tab-shell behavior**

Keep onboarding and local-database initialization gates. Change only the post-initialization destination and visible labels necessary to surface the current app. Do not delete legacy route files in this task; make them unreachable from ordinary launch/navigation and list them for later removal after QA.

- [ ] **Step 4: Document the runtime**

In `SETUP.md`, name the integration worktree path discovered in Task 2 and specify:

```bash
cd /Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa/.worktrees/feature-current-experience/mobile
npm install
npm start
```

State explicitly that `docs/reimagine-product-scope` is not a mobile runtime. Update `docs/v1-status.md` to describe the current local-first + Chats + input-state baseline.

- [ ] **Step 5: Run checks and commit**

Run: `cd mobile && npm test -- --runInBand src/navigation && npm run typecheck`

Expected: PASS.

```bash
git add mobile/app SETUP.md docs/v1-status.md docs/features/current-experience-consolidation-qa.md
git commit -m "docs: make current experience the maintained runtime"
```

---

### Task 8: Run full verification and prepare device QA

**Files:**
- Modify: `docs/features/current-experience-consolidation-qa.md`
- Modify: `docs/reconciliation/current-experience-inventory.md`
- Modify: `docs/workflow.md`
- Modify: `docs/superpowers/plans/2026-08-16-current-experience-consolidation.md`

**Interfaces:**
- Consumes: the complete integration branch.
- Produces: reproducible verification evidence and an explicit Baah device-QA checklist.

- [ ] **Step 1: Run repository and backend/shared verification**

```bash
npm run verify:workflow
npm test --workspace=backend -- --runInBand
npm run build --workspace=backend
```

Expected: all available commands exit 0. Shared contract compilation remains covered through backend/mobile TypeScript until the repository defines a standalone shared script.

- [ ] **Step 2: Run complete mobile verification**

```bash
cd mobile
npm test -- --runInBand
npm run typecheck
```

Expected: all exit 0. Missing browser Storybook automation is recorded as a gap; native-only component behavior is covered in real-screen device QA and is not called a browser pass.

- [ ] **Step 3: Perform a destructive-diff guard review**

```bash
git diff --stat edb0b3d6c5b5bfdfc8903df4b9c6328f11864537..HEAD
git diff --name-status edb0b3d6c5b5bfdfc8903df4b9c6328f11864537..HEAD
bash scripts/audit-current-experience.sh
git diff --check
```

Review every deletion. Confirm the ledger maps every accepted source responsibility to an integration commit and that no local-first platform directory disappeared through branch reconciliation.

- [ ] **Step 4: Write exact device-QA steps**

The QA document must require Baah to verify:

1. cold launch shows the current experience;
2. navigation labels and Inter typography match the current design system;
3. Chats groups conversations and opens the selected local conversation;
4. Back and Reply preserve conversation identity;
5. text, voice, pause, resume, discard, transcription, retry, and submit states work;
6. offline/private local capture remains local;
7. loading, empty, error, long-text, safe-area, keyboard, and accessibility-text cases remain usable;
8. `npm run storybook:web` opens the design-system catalog in a browser, ordinary Taisa navigation exposes no catalog/gallery route, and native-only components work in their real screens.

- [ ] **Step 5: Move workflow to Review + QA and commit evidence**

Set the Active Work row to `Review + QA`, set this plan's status to `Complete — awaiting device QA`, and commit only evidence/status files:

```bash
git add docs/features/current-experience-consolidation-qa.md docs/reconciliation/current-experience-inventory.md docs/workflow.md docs/superpowers/plans/2026-08-16-current-experience-consolidation.md
git commit -m "docs: prepare current experience for QA"
```

---

### Task 9: Review, Ship, and clean up only after approval

**Files:**
- Modify after merge: `docs/workflow.md`, `docs/v1-status.md`, `docs/reconciliation/current-experience-inventory.md`

**Interfaces:**
- Consumes: passing Task 8 evidence and Baah's explicit device-QA/Ship approval.
- Produces: verified canonical `main`, an accounted branch ledger, and safe cleanup of only merged/recoverable worktrees.

- [ ] **Step 1: Invoke required completion skills**

Use `superpowers:requesting-code-review` and address every blocking finding. Then use `superpowers:verification-before-completion` and rerun the complete Task 8 matrix from a clean integration worktree.

- [ ] **Step 2: Stop at the Ship gate**

Present review findings, command evidence, device-QA status, integration SHA, remote status, and the list of proposed cleanup targets. Do not push, merge, or delete based only on Plan approval.

- [ ] **Step 3: After explicit Ship approval, invoke branch-finishing workflow**

Use `superpowers:finishing-a-development-branch`, push `feature/current-experience`, create/update a PR targeting `main`, verify its base and checks, and squash-merge with title:

```text
feat: consolidate current Taisa experience
```

- [ ] **Step 4: Verify canonical state before cleanup**

Fetch remote state; confirm local `main`, `origin/main`, PR merge SHA, and the expected tree agree. For every old branch, prove its accepted commits are present by ancestry or patch equivalence and prove dirty/untracked files were preserved or intentionally rejected in the ledger.

- [ ] **Step 5: Remove only safe targets and record the result**

Delete only fully accounted merged branches and disposable clean worktrees. Never force-delete a branch with unique commits, a dirty worktree, or ambiguous files. Preserve any blocked target and report its exact blocker. Update the ledger and Active Work with the merge SHA in a final documentation commit if those updates were not included in the merged PR.

---

## Follow-on Product slice

After this plan passes device QA and Ship, return to DESIGN for the Chats-to-thread expanding-card interaction. Pull the thread Figma frame and motion annotations, confirm reduced-motion and reverse-navigation behavior, then write a separate Product implementation plan against canonical `main`. That plan may use Reanimated 4, but it must keep `/thread/[id]` authoritative and must not reintroduce parallel chat state into the list screen.
