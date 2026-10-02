# SwiftUI Migration Program Ledger

**Updated:** 2026-10-02
**Candidate:** `origin/preview/taisa` at `719180012de745e3b507ed93eadbe7d8a951331c`
**Status:** Program 0 Build; source reconciliation complete, parity catalog next

## Program stages

| Program | Scope | Status | Prerequisite | Branch / plan | Next gate | Evidence |
|---|---|---|---|---|---|---|
| 0 | Baseline freeze and parity evidence | Build | Approved native-rebuild design | `docs/swiftui-native-rebuild`; `2026-10-02-swiftui-program-0-baseline-freeze.md` | Baah baseline-freeze approval after catalog/media evidence | `baseline-manifest.json`; `source-dispositions.json`; this ledger |
| 1 | Native foundation and feasibility | Not planned | Program 0 Ship | — | Separate Scope and Plan approval | — |
| 2 | Shared local platform | Not planned | Program 1 Ship | — | Separate Scope and Plan approval | — |
| 3 | Product vertical slices | Not planned | Required Program 1–2 capabilities | — | Separate plan approval for each major slice | — |
| 4 | Motion and visual parity | Not planned | Applicable Product slices | — | Separate Scope and Plan approval | — |
| 5 | Release and cutover | Not planned | Programs 0–4 accepted | — | Separate Plan and Ship approval | — |

Approval of Program 0 does not authorize any later program, slice, dependency selection, Swift implementation, release, or cutover.

## Source accounting

This table mirrors the captured manifest. `Unique` is the count versus `origin/main`, not a claim that every patch is absent from the candidate; patch-equivalent and evolved integrations are called out in the recommendation.

| Source | HEAD | Upstream | Dirty | Unique | Manifest disposition | Affected behavior | Resolution |
|---|---:|---|---:|---:|---|---|---|
| `codex/chat-close-auth-handoff` | `8559a55` | none | 3 | 72 | accounted | Recorder start recovery, Face ID startup shielding, audio handoff retry; uncommitted main-navigation changes | Candidate contains evolved committed behavior and the exact dirty navigation behavior |
| `design-system` | `f50cba1` | none | 4 | 0 | excluded | Uncommitted root/backend/mobile dependency-manifest experiment | Not served product behavior; worktree preserved |
| `docs/project-memory-system` | `10abf2e` | `origin/docs/project-memory-system` | 0 | 5 | excluded | Repository memory and workflow documentation | Repository-process work; branch preserved |
| `docs/reimagine-product-scope` | `fede158` | none | 31 | 7 | accounted | Architecture/current-experience records, tab-transition fix, extensive uncommitted workflow and package changes | Candidate contains the product transition; incompatible dependency/process experiments remain preserved |
| `docs/swiftui-native-rebuild` | `d21ad86` | none | 2 | 5 | excluded | This migration program and evidence tooling | Governs migration; not React Native product parity |
| `feature/automatic-provider-fallback` | `d8157ec` | `origin/feature/automatic-provider-fallback` | 0 | 17 | accounted | Coaching-provider fallback and quality gates | All patches have candidate equivalents |
| `feature/chat-input-states` | `220e29c` | none | 5 | 30 | accounted | Chat composer, recorder lifecycle, discard flow; uncommitted reply-transition work | Committed work reconciled; dirty legacy reply flow superseded by candidate architecture |
| `feature/chats` | `8ae6347` | none | 1 | 8 | accounted | Chats list and thread presentation; generated `mobile/node_modules` only is dirty | Reconciled behavior present; generated directory excluded |
| `feature/combined-home-insights-platform` | `de27548` | `origin/main` | 0 | 25 | accounted | Governed Home storage, repositories, contracts, operations | HEAD is candidate ancestry |
| `feature/combined-home-insights-product` | `2f3020c` | none | 0 | 151 | excluded | Candidate history plus one new Home-attention DS foundation commit | Extra commit was never served; preserved as post-freeze work |
| `feature/design-system-evolution` | `3be2fd7` | `origin/main` | 0 | 1 | accounted | Recovered typography, Storybook, and DS experiments | Existing reconciliation maps accepted and rejected responsibilities |
| `feature/design-system-foundation-and-enforcement` | `5384cad` | `origin/main` | 2 | 23 | accounted | Semantic DS foundation in candidate; uncommitted liquid-glass surface/test changes | HEAD is candidate ancestry; unserved dirty compatibility tweak remains preserved |
| `feature/liquid-glass-buttons` | `5d92dbc` | `origin/main` | 0 | 9 | accounted | Liquid-glass capability, controls, ownership tests | Evolved implementations are in candidate |
| `feature/secondary-icon-button` | `219f7c0` | none | 0 | 2 | accounted | Fluid secondary icon button and active-recording experience | Evolved components are in candidate |
| `fix/bottom-navigation-fades` | `56fbb50` | none | 0 | 3 | accounted | Tab-fade overlap, backdrop placement, closing-chat destination bounce | Later candidate navigation implements these behaviors |
| `fix/bottom-navigation-response` | `be7d69b` | none | 0 | 25 | accounted | Immediate bottom-tab navigation response | Represented by candidate commit `1a9c72c` |
| `fix/glass-elevation-keyboard-surfaces` | `a4f6246` | `origin/fix/glass-elevation-keyboard-surfaces` | 0 | 63 | accounted | Glass elevation, keyboard surface polish, tactile feedback | Evolved implementations are in candidate |
| `fix/main-nav-tap-fade` | `d78e24b` | none | 0 | 68 | accounted | Crossfade for tapped main destinations | HEAD is candidate ancestry |
| `fix/nav-haptic-microphone-recovery` | `368b46c` | none | 0 | 78 | accounted | Navigation haptics, microphone/start recovery, closing-sheet reveal | All source patches have candidate equivalents |
| `integration/recent-experience-preview` | `b8ea90e` | none | 1 | 26 | accounted | Integrated interactive chat navigation; generated `mobile/node_modules` only is dirty | Candidate-equivalent patches present; generated directory excluded |
| `main` | `e1bcbf7` | `origin/main` | 0 | 0 | accounted | Canonical main baseline | Already accounted by `e1bcbf7` |
| `preview/taisa` | `7191800` | `origin/preview/taisa` | 0 | 150 | accounted | Exact canonical React Native preview candidate | Candidate itself |
| `refactor/shared-chat-recording-shell` | `686611c` | `origin/main` | 0 | 25 | accounted | Shared chat/recording shell and interactive navigation | Evolved implementations are in candidate |

## Critical-fix parity

| React Native commit | Native owner | Regression evidence | Status |
|---|---|---|---|
| — | — | No source requires a critical pre-freeze fix | None |

## Accepted differences

| Catalog ID | Severity | Decision owner | Reason | Approval evidence |
|---|---|---|---|---|
| — | — | — | No differences accepted | — |

## Decision log

| Date | Decision | Owner | Evidence |
|---|---|---|---|
| 2026-10-02 | Approve the revised native-rebuild design and Program 0 plan only; no later program or Swift implementation is authorized | Baah | Conversation approval; commits `0b13b11` and `6f51c79` |
| 2026-10-02 | Stop before selecting a baseline until every unresolved source is explicitly accounted, excluded, or classified as a critical fix | Program 0 plan | `2026-10-02-swiftui-program-0-baseline-freeze.md`, Task 3 |
| 2026-10-02 | Approve the recommended source dispositions; reconcile held sources without changing preserved worktrees | Baah | Conversation approval; `source-dispositions.json` |
