# APF-93 native source reconciliation

Source cutoff: 2026-11-19. This document records source selection, not QA or Ship approval. Live acceptance and blockers remain in Linear APF-93 and APF-94.

## Post-cutoff review on 2026-11-20

- Repository audit at Preview revision `cf8e00a4963dd0caecc89f9f301045d3d8c9064c` inspected all 65 live worktrees and found no uncommitted files. Five `/private/tmp` worktree records are prunable because their directories no longer exist; they contain no uncommitted filesystem state. No branch was merged, deleted or rewritten during the audit.
- PR #58 remains published at `da4eaefc485d9347e972be5772f2af7cc62253c3`. Canonical Preview is `e47c4e09af873e268e7160de5457f0d34b017c32`, which adds the shipped APF-97 CI repair to the same Product tree. The clean current-main replacement started at `af1964e777fe30d8e1f980a1ee11696cfc09bd67`. Review repair `e610ba28df46d924894bab6ca4f03c6797134468` preserves legacy action due dates in the device's local calendar. The frozen candidate is the branch head containing this manifest and that repair.
- Profile branch `codex/apf-49-profile-redesign-preview-repair` retained the approved `ProfileAvatarFallback` behavior. The candidate uses Baah's replacement `avatar.png` at the shared 48-point default button size. Its later CI-only commits stay on their CI branch.
- Tasks branch `codex/apf-69-tasks-ui` retained the task composer overlay and Tasks-only Home behavior. The candidate keeps newer Profile and design-system contracts instead of the branch's older raw controls.
- Button branches `feature/apf-75-native-ds-adoption` and `fix/glass-elevation-keyboard-surfaces` remain source records. The candidate owns the later 48-point default, 36-point small, shared glass surface, and keyboard overlay repair.
- Navigation repair branches `fix/nav-haptic-microphone-recovery` and `integration/recent-experience-preview` remain source records. The candidate keeps active navigation icons black and inactive navigation icons at approved Grey 400.
- Audio verification `codex/apf-90-backup-exclusion-verification` remains represented by the selected audio regression source. APF-92 is still superseded by the Profile redesign. APF-96, APF-97 and the later APF-49 workflow commits are CI-only and do not add Preview Product behavior.
- Search stays hidden until APF-52 implements native local search. The candidate keeps conditional Drafts access.

## Selected sources

| Front | Exact source | Treatment |
| --- | --- | --- |
| Main and workflow authority | `b5f98d96c97a37df24082eb4a8e5ae20db7b65be` | Base. Retain Matt-first routing, cumulative Preview policy, and the APF-97 simulator-runtime repair. |
| Tasks, Home and Actions/Goals | `067a5ccd0e92f49985634529a213dff8719d70af`, plus preserved dirty snapshot `3b935025834ca427330bbf767e8033b7e5209164` | Include the latest task composer/detail, Tasks-only Home, v9 storage and provenance validation. Preserve newer rich button APIs while delegating rendering to the shared foundation. |
| Profile and Bio | latest source `887939e1c`, equivalent Product content to preserved snapshot `5f64a476f21874e22fc1c4bea92dff8e46081d94` | Include redesigned Profile, field validation, multiline Bio and invalid-draft retention. New source commits only reconcile current main workflow authority, already retained here. |
| Typography | `eff8c4ea18082a964c25b3c937334735b2c5c772` | Include global Inter UI / Scoutie Sans display ownership, accessible navigation titles, combined Tasks/Profile roles and package font resources. |
| Control enforcement | `7748a2e5d8180b4538ed81a7757463232a35e315` | Retain latest scanner and bypass fixtures. Product and composite DS controls delegate to the common button constructor. No legacy Button fingerprints remain. |
| Shared native buttons and recovery | `ba88bc442f89fc9d41757f53dd5aa24dd9fc6e82` | Compose with latest Tasks/Profile APIs. All standalone, icon and floating controls share Record's native glass style. Capsule default and circle icon controls. Content actions delegate through the same constructor with content presentation. Native dialog/menu adapters preserve concrete Button values and cancel/destructive semantics. |
| Audio regression | `4d802861e`, content-equivalent to preserved snapshot `917970a8b99abb893163a967dbb3c3c54c6a258e` | Include persisted macOS backup-exclusion verification and pre-finalization negative control; retain public resource-value checks on iOS. |
| Simulator annotations | `8630f247ad4e534f9908ef21db3910583980ccce` | Include dev-only annotated simulator review tooling and pinned dependency lockfile. No production app dependency. |

## Explicit replacements and exclusions

- Canonical Preview cutoff is `a3e76192406e14b6b105dc7b6666cbf25a68de23`. Its 58 changed files relative to the common base are all represented by newer selected candidate changes; no Preview-only file is missing. Latest APF-69 Tasks source replaces the earlier Actions/Goals presentation. Existing navigation, conversation, recovery, insights, storage and runtime capabilities remain accounted for through main and the newer selected sources.
- Senior Self `6ac3f01f7fd22ba748febb7bc766b68768305646` adds no outstanding feedback UI changes beyond the selected Tasks source. Its older schema and provenance implementation must not replace v9 storage and stronger source validation. Preserve its source ref without importing obsolete code.
- APF-92's canceled generic You navigation repair is superseded by redesigned APF-49 Product content. Preserve adaptive phone navigation under the approved APF-74 iPhone-only contract.
- Recording-glow drift snapshot `02a8cad499887135c0bf7eafb8ee37b716120152` is preserved, but does not replace shipped frequency behavior and calibrated glow values from current main. The older draft would simplify current frequency behavior and revert tuning.
- Secondary outline/shadow rendering in the dirty Tasks snapshot is replaced by the user's later instruction that every action button share Record's foundation. Size, icon color, selected/disabled/loading state, accessibility, and source-compatible elevation arguments remain supported; native style owns elevation.
- Historical, legacy and migrated worktree copies are preserved. They are not independent latest candidates merely because they remain on disk. No original worktree was reset, stashed, committed or deleted.

## Review boundaries

The source candidate remains main-based and contains no Preview-only ancestry. A separate integration-only Preview branch must retain canonical Preview history and explicitly account for replacements above. Main merge, canonical publication and device installation require the applicable verification and QA gates.

Native verification must use this combined revision, not screenshots or CI from a constituent source branch. The DS-only Swift 6 harness excludes Canvas `#Preview` macros and does not prove full app compilation. The Foundation-only source-contract harness does not run model integration or UI tests. Phone dialogs retain explicit Cancel coverage. Recovery navigation assertions require a phone Back control under the approved APF-74 iPhone-only contract.
