# Current Experience Reconciliation Inventory

**Captured:** 2026-08-16, before integration work
**Canonical base at capture:** `main` at `3dcdcf686a00ceca021ab2919a378b42a04aa876`

This ledger is the preservation record for the current-experience consolidation. A source branch or worktree remains protected until its accepted work is mapped to an integration commit and later verified on canonical `main`.

| Source | HEAD | Upstream | Dirty/untracked at capture | Unique work | Disposition | Accounted by |
|---|---|---|---|---|---|---|
| `feature/local-first-coaching-platform` | `edb0b3d6c5b5bfdfc8903df4b9c6328f11864537` | `origin/feature/local-first-coaching-platform` (ahead 12) | clean | 74 commits; Platform baseline | Preserve as source and integration base | Integration ancestry from `edb0b3d`; verified through `54df7e2` |
| `feature/chats` | `8ae63478d1ba4b3b192256a8b5293f3e11ee6b55` | none | untracked `mobile/node_modules/` only | 8 commits; Chats UI chain | Port by responsibility | `dd6136f`, `b460094`, `54df7e2` |
| `feature/chat-input-states` | `2a8c79fbec4105a6a1b0a06c77cbe46486b48881` | none | clean | 29 commits including the 8 Chats commits | Preserve as superseded reference; do not port server-authoritative implementation | Local-first mapping below; Chats presentation in `b460094` |
| `feature/design-system-evolution` | `3be2fd7c` | `origin/main` (ahead 1) | clean after recovery commit | Typography, stories, browser/native catalog experiments, DS docs/tooling | Accepted browser/typography work ported; rejected/deferred items recorded below | Recovery `3be2fd7`; integration `d785989` |
| `design-system` | `f50cba16d8cb89b0eb6c763eb7add9bbb5dc5574` plus working tree | none | 3 modified manifests and untracked root `package-lock.json` | Older dependency experiment in external worktree | Preserve untouched pending ownership decision | — |
| `docs/reimagine-product-scope` | `f6eb523aaf05ec294dea616d17dd41301eef3a68` plus working tree | none | modified `mobile/package.json` and `mobile/package-lock.json` | 9 documentation commits plus user dependency edits | Preserve dependency edits; cherry-pick approved docs later | — |

## Dirty-worktree fingerprints

Fingerprints are SHA-256 hashes of `git diff --binary` at capture time. The empty-diff hash is included for clean tracked states; untracked paths are listed separately.

| Worktree | Binary diff SHA-256 |
|---|---|
| `docs/reimagine-product-scope` | `14e6dd0e4d924a4c7edd28c2e39b2e858e1d51d36910afb6c13f908a4d136fd6` |
| `design-system` | `1556bec0a348639e76329c8b47ec316dd41b05387169e64d3ee62e855c1b4fec` |
| `feature/chat-input-states` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `feature/chats` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `feature/design-system-evolution` | `ec2406d86f3d3459f9a1a80169185df4f78192c0b299a50bff7dc1211fa82e0b` |
| `feature/local-first-coaching-platform` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |

## Untracked paths at capture

### `feature/chats`

- `mobile/node_modules/` — generated dependency directory; never stage.

### `feature/design-system-evolution`

- `docs/features/design-system-evolution.md`
- `docs/superpowers/plans/2026-08-15-design-system-evolution.md`
- `docs/superpowers/specs/2026-08-15-design-system-evolution-design.md`
- `mobile/app/design-system.tsx`
- `mobile/scripts/verify-design-system.mjs`
- `mobile/scripts/verify-production-storybook.sh`
- `mobile/src/components/ui/ChatNavBar.stories.tsx`
- `mobile/src/components/ui/CubeRefractionOverlay.stories.tsx`
- `mobile/src/components/ui/GlowDevSheet.stories.tsx`
- `mobile/src/components/ui/RecordingGlow.stories.tsx`
- `mobile/src/components/ui/TaisaReplyCard.stories.tsx`
- `mobile/src/components/ui/TopNavBar.stories.tsx`
- `mobile/src/components/ui/Typography.stories.tsx`

### `design-system`

- `package-lock.json`

## Safety notes

- The `design-system` and `feature/design-system-evolution` worktrees are distinct and both contain user work.
- `feature/chat-input-states` descends from `feature/chats`; it does not descend from the local-first platform branch.
- No source branch or worktree is approved for deletion during Build.
- The in-app `mobile/app/design-system.tsx` experiment is preserved in the source snapshot but is excluded from the approved browser-Storybook architecture.

## Platform baseline verification

Verified at `edb0b3d6c5b5bfdfc8903df4b9c6328f11864537`:

- Backend Jest: 20 suites, 242 tests passed.
- Backend TypeScript build: passed.
- Mobile Jest: 46 suites, 426 tests passed.
- Mobile TypeScript check: passed.
- Shared workspace: no standalone `build` or other npm script exists; its TypeScript contracts are exercised through the passing backend and mobile builds/checks. This is recorded as an infrastructure gap rather than a passing standalone shared check.
- Initial sandboxed backend run failed because Supertest could not bind a temporary local server (`listen EPERM 0.0.0.0`). The same suite passed outside the sandbox; no product defect was established.

## Chat-input semantic reconciliation

The source branch's `test:chat-input` and `test:chat-orchestration` scripts passed on 2026-08-16. Their guarantees were compared with the verified local-first baseline rather than copied wholesale:

| Older chat-input responsibility | Current local-first owner | Decision |
|---|---|---|
| `chatInputMachine.ts` recording/paused/typing state | `mobile/src/services/voiceComposerState.ts` plus `VoiceComposer` tests | Keep local-first owner; it adds voice-ready idle, uncertain-speech handling, terminal failure behavior, deliberate submission, and preferred-mode restoration |
| `chatActionCoordinator.ts` duplicate-action locks | recording start guard, cleanup barrier, stop session, and submission lease in `mobile/app/chat/index.tsx` and focused services | Keep local-first owners; they cover native recorder teardown and queued cleanup rather than only UI action booleans |
| `chatSubmission.ts` calls `/entries`, `/analyze`, and `/chat/*` | `mobile/src/services/privateCapture.ts` and local repositories | Reject legacy implementation because it restores server-authoritative readable data and violates the approved local-first boundary |
| `chatTranscription.ts` one-shot transcription | streaming transcription service, recording submission lease, and uncertain/no-speech outcomes | Keep local-first implementation; it has stronger recovery and privacy guarantees |
| Chat-input UI components | `VoiceComposer`, `VoiceDraftStrip`, `TranscriptCorrectionCard`, and typed `ChatSurfaces` | Keep local-first DS components; reconcile visual tokens/stories during the DS task |

No duplicate chat state machine was added. This is an intentional cleanup decision: the behavioral contract is preserved by the newer tested owners, while the older server-authoritative transport is excluded.

## Design-system reconciliation

The recovered `feature/design-system-evolution` work was classified by responsibility before integration:

| Source responsibility | Decision | Current owner |
|---|---|---|
| Inter typography and semantic type utilities | Accept and adapt | `mobile/app/_layout.tsx`, `mobile/global.css`, and `mobile/tailwind.config.js` |
| Browser component stories and safe-area/gesture preview wrappers | Accept and adapt | `mobile/.rnstorybook/` and colocated `*.stories.tsx` files |
| On-demand browser catalog | Accept with an isolated entry point | `mobile/index.ts`, `mobile/metro.config.js`, and `npm run storybook:web` |
| In-app design-system route and Account-screen link | Reject | Browser catalog is the review surface; no product route is added |
| Production/native Storybook configuration | Reject | Storybook remains development-only and environment gated |
| Skia effects and native tuning surfaces | Preserve as native-only | Documented in `docs/design-system.md`; verify in real app screens during device QA |
| Workflow edits that bypass Baah approval gates | Reject | `docs/workflow.md` remains authoritative |

Browser verification on 2026-08-16 confirmed that all 19 catalog modules render with controls and no console errors. The entry point intentionally prevents Expo Router routes—and therefore native-only Skia modules—from entering the browser catalog bundle. Mobile verification after reconciliation: 48 suites, 433 tests passed; TypeScript and the design-system verifier passed.

## Final integration verification

Verified on `feature/current-experience` at `54df7e2` on 2026-08-16:

- Workflow verifier passed.
- Backend Jest: 20 suites, 242 tests passed.
- Backend TypeScript build passed.
- Mobile Jest: 49 suites, 435 tests passed.
- Mobile TypeScript check passed.
- Design-system verifier passed for 19 catalog modules.
- Browser catalog rendered its story tree and controls with no console errors.
- Destructive-diff review found 42 changed paths, 2,028 insertions, 72 deletions, and no deleted files or lost local-first platform directory.
- `scripts/audit-current-experience.sh` and `git diff --check` passed; all source branches/worktrees remain preserved.

The root package does not declare `mobile` as an npm workspace, so mobile commands must run from `mobile/`; this is a command/documentation constraint, not a failed product check. `npm audit` currently reports 37 dependency findings (2 low, 17 moderate, 17 high, 1 critical); no automatic audit fix was applied because dependency upgrades require separate review.
