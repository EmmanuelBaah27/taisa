# APF-93 native source reconciliation

Source cutoff: 2026-11-19. This document records source selection, not QA or Ship approval. Live acceptance and blockers remain in Linear APF-93 and APF-94.

## Selected sources

| Front | Exact source | Treatment |
| --- | --- | --- |
| Main and workflow authority | `9dc5fccd0939b3ca5c227f4d358fac10d07535fa` | Base. Retain Matt-first routing and cumulative Preview policy. |
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
- APF-92's canceled generic You navigation repair is superseded by redesigned APF-49 Product content. Preserve adaptive phone push and iPad split navigation.
- Recording-glow drift snapshot `02a8cad499887135c0bf7eafb8ee37b716120152` is preserved, but does not replace shipped frequency behavior and calibrated glow values from current main. The older draft would simplify current frequency behavior and revert tuning.
- Secondary outline/shadow rendering in the dirty Tasks snapshot is replaced by the user's later instruction that every action button share Record's foundation. Size, icon color, selected/disabled/loading state, accessibility, and source-compatible elevation arguments remain supported; native style owns elevation.
- Historical, legacy and migrated worktree copies are preserved. They are not independent latest candidates merely because they remain on disk. No original worktree was reset, stashed, committed or deleted.

## Review boundaries

The source candidate remains main-based and contains no Preview-only ancestry. A separate integration-only Preview branch must retain canonical Preview history and explicitly account for replacements above. Main merge, canonical publication and device installation require the applicable verification and QA gates.

Native verification must use this combined revision, not screenshots or CI from a constituent source branch. The DS-only Swift 6 harness excludes Canvas `#Preview` macros and does not prove full app compilation. The Foundation-only source-contract harness does not run model integration or UI tests. iPad cancellation uses native popover dismissal; phone dialogs retain explicit Cancel coverage. Recovery navigation assertions distinguish a split sidebar toggle from a phone Back control.
