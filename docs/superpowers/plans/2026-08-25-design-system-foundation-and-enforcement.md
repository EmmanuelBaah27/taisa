# Design System Foundation and Enforcement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Use `superpowers:subagent-driven-development` only if Baah explicitly authorizes subagents. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Taisa's semantic colors, readable typography, foundational components, and automated compliance gate the mandatory basis of all Product UI.

**Architecture:** A JSON token registry is the single value source consumed by NativeWind and a typed TypeScript facade. Semantic UI components own recurring visual decisions, while a fixture-tested Node verifier rejects bypasses and validates component registration, documentation, stories, and expiring technical exceptions. Current shared components and screens migrate before the same verifier becomes mandatory in workflow, CI, preview integration, and Ship.

**Tech Stack:** React Native, Expo managed workflow, NativeWind 4, Tailwind CSS 3, TypeScript 5.9, Storybook React Native 10, Node.js built-in test runner, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-25-design-system-foundation-and-enforcement-design.md`

**Status:** Awaiting Baah plan approval

## Global constraints

- Preserve Taisa's current light visual direction; do not redesign navigation, interactions, data flows, coaching behavior, or backend contracts.
- Default body text is 16px; 14px is secondary UI; 12px is genuinely tertiary metadata only.
- Product code uses semantic color and typography roles; raw colors and independently selected font sizes/weights are prohibited.
- NativeWind remains the Product styling system. Do not add `StyleSheet.create()`.
- Keep Expo managed. Do not run `expo run:ios` or eject.
- Design-system components contain presentation and interaction mechanics only—no stores, navigation decisions, data fetching, or business logic.
- New reusable components ship with typed props, exports, documentation, Storybook coverage, verifier registration, and a real consuming feature.
- Technical exceptions are exact-file, exact-rule, owned, justified, and expiring; broad directory exemptions and inline suppressions are invalid.
- Do not implement from the dirty `docs/reimagine-product-scope` worktree. Execution begins in a clean `feature/design-system-foundation` worktree created from current `origin/main` after the current-experience consolidation dependency is reconciled.

## Design-system inventory for this plan

**Reuse and align:** `Button`, `Input`, `Card`, `Badge`, `Icon`, liquid-glass action surfaces, navigation surfaces, chat surfaces, and recording surfaces.

**New approved foundations:** semantic `Text`; `Screen`, `Stack`, `Row`, `Section`, and `Divider` only when the baseline inventory confirms the repeated uses already identified in current screens.

**Classify and migrate:** `DigestCard`, `SearchBar`, `TaisaCard`, `ThemeTag`, `ThreadResumeAction`, `ThreadRow`, `VoiceButton`, and `WorkspaceHeader`.

**Do not build speculatively:** tables, menus, toast systems, date pickers, or other components not consumed by the current experience.

---

### Task 1: Establish a clean canonical execution baseline

**Files:**
- Create: `docs/design-system-audit.md`
- Modify: `docs/workflow.md`

**Interfaces:**
- Consumes: approved scope and design; canonical `origin/main`; current-experience consolidation inventory.
- Produces: a clean feature worktree and a checked-in baseline audit listing every Product file, violation category, and component classification.

- [ ] **Step 1: Verify repository and preview state without modifying either**

Run:

```bash
git fetch --prune origin
git status --short --branch
git worktree list --porcelain
git branch -avv
git -C .worktrees/preview-taisa status --short --branch
git -C .worktrees/preview-taisa rev-parse HEAD
git rev-list --left-right --count origin/main...preview/taisa
```

Expected: remote state is readable; preview is clean and matches its remote. Stop if the canonical implementation architecture is not accounted for by current-experience consolidation or if unique work is at risk.

- [ ] **Step 2: Create the isolated implementation worktree**

Invoke `superpowers:using-git-worktrees`, then create `feature/design-system-foundation` from updated `origin/main`. Do not reuse the dirty documentation worktree.

- [ ] **Step 3: Record the baseline audit**

Create `docs/design-system-audit.md` with these tables populated from `rg` results:

```markdown
# Design System Migration Audit

**Baseline commit:** Copy the exact 40-character output of `git rev-parse HEAD` here before committing this audit.

## Typography violations
| File | Raw Text import | Legacy size/weight | Arbitrary size |

## Color violations
| File | Raw color | Palette utility | Required semantic role |

## Component classification
| Component | Reuse | Modify | Move to ui | Move to features | Screen-specific |

## Technical exceptions
| File | Rule | Native API reason | Owner | Review date |
```

Replace the instruction in the SHA field with the actual baseline SHA before verification.

- [ ] **Step 4: Verify the audit is complete**

Run:

```bash
rg -n "StyleSheet\.create|#[0-9A-Fa-f]{3,8}|rgba?\(|hsla?\(|oklch\(|text-(xs|sm|base|lg|xl)|text-\[|font-(normal|medium|semibold|bold)" mobile/app mobile/src/components
rg -n "Copy the exact|TBD|TODO" docs/design-system-audit.md
```

Expected: the first command's findings are represented in the audit; the second returns no matches.

- [ ] **Step 5: Commit the auditable baseline**

```bash
git add docs/design-system-audit.md docs/workflow.md
git commit -m "docs: audit design system migration baseline"
```

### Task 2: Create the authoritative token contract

**Files:**
- Create: `mobile/design-system/tokens.json`
- Create: `mobile/src/design-system/tokens.ts`
- Create: `mobile/src/design-system/tokens.test.ts`
- Modify: `mobile/tailwind.config.js`
- Modify: `mobile/global.css`
- Modify: `mobile/tsconfig.json`

**Interfaces:**
- Produces: `colorTokens`, `typographyTokens`, `ColorRole`, and `TypographyRole` for components; JSON values for Tailwind configuration.
- Consumes: retained light-theme values from the approved design and audit.

- [ ] **Step 1: Write the failing token-contract test**

Define tests that assert the exact typography roles and sizes:

```ts
expect(typographyTokens.body.fontSize).toBe(16);
expect(typographyTokens.label.fontSize).toBe(14);
expect(typographyTokens.metadata.fontSize).toBe(12);
expect(Object.keys(typographyTokens)).toEqual([
  'display', 'heading', 'subheading', 'body', 'bodyStrong',
  'label', 'labelStrong', 'metadata', 'metadataStrong',
]);
expect(colorTokens.text).toHaveProperty('primary');
expect(colorTokens.surface).toHaveProperty('app');
expect(colorTokens.action).toHaveProperty('primary');
expect(colorTokens.status).toHaveProperty('danger');
```

- [ ] **Step 2: Run the narrow test and confirm failure**

Run: `cd mobile && npx tsc --noEmit`

Expected: failure because `src/design-system/tokens.ts` does not exist.

- [ ] **Step 3: Add the value registry and typed facade**

`tokens.json` must contain only primitives plus semantic color and typography maps. `tokens.ts` imports that JSON, validates it with explicit `satisfies` contracts, freezes exports, and derives role unions from keys. Do not duplicate values in `tailwind.config.js`.

- [ ] **Step 4: Make NativeWind consume the registry**

Require `./design-system/tokens.json` from `tailwind.config.js` and map semantic roles to stable utilities such as `bg-background`, `bg-surface-elevated`, `text-foreground`, `text-muted-foreground`, `border-border`, `bg-primary`, and status counterparts. Replace typography CSS values with registry-aligned utilities named for the approved roles.

- [ ] **Step 5: Run token and type verification**

Run:

```bash
cd mobile && npx tsc --noEmit
node --test src/design-system/tokens.test.ts
```

Expected: both pass. If the installed Node cannot execute TypeScript tests directly, compile the test with the mobile TypeScript configuration and run the emitted JavaScript from a temporary directory; do not add a runtime dependency solely for this test.

- [ ] **Step 6: Commit the token contract**

```bash
git add mobile/design-system mobile/src/design-system mobile/tailwind.config.js mobile/global.css mobile/tsconfig.json
git commit -m "feat(ds): establish semantic token contract"
```

### Task 3: Build semantic Text and foundation stories

**Files:**
- Create: `mobile/src/components/ui/Text.tsx`
- Create: `mobile/src/components/ui/Text.stories.tsx`
- Create: `mobile/src/components/ui/Text.test.tsx`
- Modify: `mobile/src/components/ui/index.ts`

**Interfaces:**
- Consumes: `TypographyRole`, `ColorRole`, and token utilities from Task 2.
- Produces: `Text({ role?: TypographyRole, color?: TextColorRole, ...TextProps })`, defaulting to `role="body"` and `color="primary"`.

- [ ] **Step 1: Write failing semantic Text contract tests**

Cover default body, every approved role, approved semantic text colors, `numberOfLines`, accessibility font scaling, and rejection by TypeScript of numerical sizes or arbitrary class overrides.

- [ ] **Step 2: Confirm the test/type failure**

Run: `cd mobile && npx tsc --noEmit`

Expected: failure because the semantic `Text` export is absent.

- [ ] **Step 3: Implement the minimal semantic component**

Wrap React Native `Text`, map roles and colors through closed typed records, default `allowFontScaling` to React Native behavior, and do not expose `style.fontSize`, `style.fontWeight`, or unrestricted typography `className` as public styling escape hatches.

- [ ] **Step 4: Add Storybook coverage**

Create stories showing all roles, primary/secondary/tertiary/inverted/status colors, multiline wrapping, and accessibility-length content. The default story must visibly demonstrate 16px body copy beside 14px labels and 12px metadata.

- [ ] **Step 5: Verify and commit**

Run: `cd mobile && npx tsc --noEmit`

Expected: pass.

```bash
git add mobile/src/components/ui/Text.tsx mobile/src/components/ui/Text.stories.tsx mobile/src/components/ui/Text.test.tsx mobile/src/components/ui/index.ts
git commit -m "feat(ds): add semantic text foundation"
```

### Task 4: Align existing foundational components

**Files:**
- Modify: `mobile/src/components/ui/Button.tsx`
- Modify: `mobile/src/components/ui/Input.tsx`
- Modify: `mobile/src/components/ui/Card.tsx`
- Modify: `mobile/src/components/ui/Badge.tsx`
- Modify: `mobile/src/components/ui/Icon.tsx`
- Modify: matching `*.stories.tsx` files
- Create or modify: matching component contract tests

**Interfaces:**
- Consumes: semantic `Text`, color roles, and typography roles.
- Produces: foundational components with closed semantic variants and complete default, pressed, disabled, loading, error, focus, and selected states where applicable.

- [ ] **Step 1: Add failing contract tests for each component**

Assert that labels use semantic Text, Icon accepts semantic `colorRole` for Product use, Input exposes label/helper/error states, and components do not accept raw Product colors or independent typography props.

- [ ] **Step 2: Confirm current contracts fail**

Run: `cd mobile && npx tsc --noEmit`

Expected: failures identifying old props or missing semantic props.

- [ ] **Step 3: Migrate one component at a time**

Order: Text consumers in Button → Input → Card → Badge → Icon. After each component, update its story with all supported states and run `npx tsc --noEmit`. Preserve public behavior when a compatible semantic mapping exists; record breaking visual/API changes before proceeding and obtain Baah approval under the DS rules.

- [ ] **Step 4: Verify foundation coverage**

Run:

```bash
cd mobile && npx tsc --noEmit
rg -n "#[0-9A-Fa-f]{3,8}|rgba?\(|text-(xs|sm)|font-(medium|semibold|bold)" src/components/ui/{Button,Input,Card,Badge,Icon}.tsx
```

Expected: TypeScript passes; `rg` returns no unapproved Product styling matches.

- [ ] **Step 5: Commit**

```bash
git add mobile/src/components/ui
git commit -m "refactor(ds): align foundation component contracts"
```

### Task 5: Build the fixture-tested compliance verifier

**Files:**
- Create: `scripts/design-system/verify.mjs`
- Create: `scripts/design-system/rules.mjs`
- Create: `scripts/design-system/component-registry.json`
- Create: `scripts/design-system/exceptions.json`
- Create: `scripts/design-system/__tests__/verify.test.mjs`
- Create: `scripts/design-system/__fixtures__/pass/semantic-screen.tsx`
- Create: `scripts/design-system/__fixtures__/fail/raw-color.tsx`
- Create: `scripts/design-system/__fixtures__/fail/raw-text.tsx`
- Create: `scripts/design-system/__fixtures__/fail/legacy-type.tsx`
- Create: `scripts/design-system/__fixtures__/fail/stylesheet.tsx`
- Create: `scripts/design-system/__fixtures__/fail/expired-exception.tsx`
- Modify: `package.json`

**Interfaces:**
- Produces: `npm run verify:design-system`, exiting 0 only when all checks pass and emitting `path:line rule message` failures.
- Consumes: token registry, component barrel, stories, documentation headings, registry, and exact exceptions.

- [ ] **Step 1: Write failing verifier fixture tests**

Use `node:test` and `assert/strict`. Each failing fixture must assert its exact rule ID: `no-raw-color`, `semantic-text-only`, `no-legacy-type`, `no-stylesheet-create`, and `exception-expired`. The passing fixture must produce zero findings.

- [ ] **Step 2: Run tests and confirm failure**

Run: `node --test scripts/design-system/__tests__/verify.test.mjs`

Expected: failure because verifier modules do not exist.

- [ ] **Step 3: Implement deterministic scanning rules**

Scan only versioned `.ts`, `.tsx`, `.js`, `.jsx`, `.css`, and JSON files under configured Product roots. Ignore dependencies, generated Storybook requires, fixtures during repository mode, and build output. Parse line positions deterministically. Keep rule definitions in `rules.mjs`; orchestration and reporting stay in `verify.mjs`.

- [ ] **Step 4: Implement exact exceptions**

Each exception entry must have:

```json
{
  "file": "mobile/src/components/ui/RecordingGlow.tsx",
  "rule": "no-raw-color",
  "reason": "Gradient API requires concrete color strings",
  "owner": "Taisa Design System",
  "expires": "2026-11-25"
}
```

Reject missing fields, directory globs, expired dates, and exceptions that match no current finding.

- [ ] **Step 5: Add component registry checks**

For each registered visually reviewable UI component, require the implementation file, barrel export, documentation heading, and colocated story. Registry entries explicitly mark low-level non-Storybook rendering utilities so they are reviewed without pretending they have conventional visual contracts.

- [ ] **Step 6: Expose the root command and run fixture tests**

Add:

```json
"verify:design-system": "node scripts/design-system/verify.mjs"
```

Run: `node --test scripts/design-system/__tests__/verify.test.mjs`

Expected: all fixture tests pass.

- [ ] **Step 7: Run against the repository and record real failures**

Run: `npm run verify:design-system`

Expected at this stage: nonzero with actionable findings limited to audited migration work. Do not add broad exceptions to force green.

- [ ] **Step 8: Commit the verifier**

```bash
git add package.json scripts/design-system
git commit -m "test(ds): enforce semantic product styling"
```

### Task 6: Migrate shared and legacy visual components

**Files:**
- Modify or move: `mobile/src/components/{DigestCard,SearchBar,TaisaCard,ThemeTag,ThreadResumeAction,ThreadRow,VoiceButton,WorkspaceHeader}.tsx`
- Modify: affected files in `mobile/src/components/ui/`
- Create: `mobile/src/components/features/` entries only for domain presentation that is reusable but not primitive
- Modify: `mobile/src/components/ui/index.ts`
- Modify: `scripts/design-system/component-registry.json`

**Interfaces:**
- Consumes: Tasks 2–5 foundations and audit classification.
- Produces: reusable presentation behind `ui/` or `features/`, with screen-specific wrappers retaining business logic.

- [ ] **Step 1: Add or update contract tests and stories before each move**

Capture current inputs and visible states so migration cannot silently change behavior. A moved component retains its old external behavior through a temporary re-export only within this task; consumers are updated before the re-export is removed.

- [ ] **Step 2: Split presentation from business behavior**

Move visual shells to the approved bucket. Keep stores, routing, data formatting, API calls, and feature decisions in wrappers or screens. Replace raw React Native Text and legacy styling with semantic foundations.

- [ ] **Step 3: Register and document each retained reusable component**

Update registry, barrel exports, Storybook stories, and `docs/design-system.md` in the same change. Classify truly one-off screen compositions in the audit rather than inventing a component.

- [ ] **Step 4: Run narrow verification after each component group**

Run:

```bash
cd mobile && npx tsc --noEmit
cd .. && npm run verify:design-system
```

Expected: TypeScript passes; verifier findings decrease and no new category appears.

- [ ] **Step 5: Commit**

```bash
git add mobile/src/components docs/design-system.md scripts/design-system/component-registry.json docs/design-system-audit.md
git commit -m "refactor(ds): migrate shared visual components"
```

### Task 7: Migrate current Product screens by journey

**Files:**
- Modify: `mobile/app/_layout.tsx`
- Modify: `mobile/app/onboarding/index.tsx`
- Modify: `mobile/app/chat/index.tsx`
- Modify: `mobile/app/recording/index.tsx`
- Modify: `mobile/app/thread/[id].tsx`
- Modify: current files under `mobile/app/(tabs)/`
- Modify: affected screen/component tests

**Interfaces:**
- Consumes: semantic Text, aligned foundations, migrated shared components, verifier.
- Produces: current Product UI with no unregistered design-system violations and unchanged business behavior.

- [ ] **Step 1: Add journey-level render or contract coverage before migration**

Cover onboarding, tab surfaces, chat/recording, and thread presentation sufficiently to preserve visible states and existing callbacks. Use existing test infrastructure; where rendering infrastructure is missing, add focused component-contract tests and report the missing journey automation rather than claiming coverage.

- [ ] **Step 2: Migrate onboarding and privacy/recovery surfaces**

Replace raw Text and arbitrary typography first. Verify default body, action labels, errors, and metadata use the approved semantic roles. Run mobile TypeScript and the verifier.

- [ ] **Step 3: Migrate tab screens**

Migrate shared headers, cards, rows, empty/loading/error states, and settings compositions. Keep tab navigation and data flow unchanged. Run mobile TypeScript and the verifier.

- [ ] **Step 4: Migrate chat, recording, and thread journeys**

Preserve gestures, animation clocks, recording behavior, transcript handling, keyboard behavior, and navigation. Register exact technical exceptions only where low-level APIs require concrete numerical styles or colors.

- [ ] **Step 5: Prove the repository has no untracked migration baseline**

Run:

```bash
npm run verify:design-system
cd mobile && npx tsc --noEmit
```

Expected: both pass. `exceptions.json` contains only exact, justified, owned, unexpired technical constraints; every exception matches a present finding before exemption.

- [ ] **Step 6: Commit**

```bash
git add mobile/app mobile/src docs/design-system-audit.md scripts/design-system/exceptions.json
git commit -m "refactor(ds): migrate current product experience"
```

### Task 8: Make compliance mandatory in documentation and CI

**Files:**
- Create: `.github/workflows/design-system.yml`
- Modify: `docs/workflow.md`
- Modify: `.claude/skills/taisa-workflow/SKILL.md`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Modify: `docs/design-system.md`
- Modify: `foundations.md`
- Modify: `scripts/verify-workflow.sh`

**Interfaces:**
- Consumes: passing root verifier.
- Produces: workflow text and CI that require the exact same command for Product Review, preview integration, and Ship.

- [ ] **Step 1: Extend workflow-verifier tests first**

Update `scripts/verify-workflow.sh` expectations so it fails unless workflow, orchestrator, agent entry point, and CI all contain the exact `npm run verify:design-system` gate and Preview/Ship blocking language.

- [ ] **Step 2: Confirm workflow verification fails**

Run: `npm run verify:workflow`

Expected: nonzero because mandatory DS enforcement text and CI are incomplete.

- [ ] **Step 3: Update workflow authority**

Require the command at Product Build completion, Review, before preview integration, and final Ship. Require every Product plan to include the DS inventory. State that missing infrastructure is a reported gap, not a pass, and that agents cannot waive the check.

- [ ] **Step 4: Add pull-request CI**

Create a workflow triggered by `pull_request` that checks out the repository, sets up the repository-supported Node version, installs only what the verifier requires, and runs:

```bash
npm run verify:design-system
```

Name the job `Design System Compliance` so branch protection can require a stable check name.

- [ ] **Step 5: Reconcile documentation to the token registry**

Update `docs/design-system.md` and `foundations.md` to use the approved roles and values. Remove conflicting typography tables and document component evolution, registry obligations, and exception policy.

- [ ] **Step 6: Verify workflow and design-system authority**

Run:

```bash
npm run verify:workflow
npm run verify:design-system
```

Expected: both pass.

- [ ] **Step 7: Confirm external branch protection**

Read the repository's branch protection/ruleset configuration. Confirm `Design System Compliance` is required for pull requests to `main`. If it is not configured and the available GitHub operation requires new external authority, stop and ask Baah for that exact authorization; do not report repository CI as branch protection.

- [ ] **Step 8: Commit**

```bash
git add .github/workflows/design-system.yml docs/workflow.md .claude/skills/taisa-workflow/SKILL.md AGENTS.md CLAUDE.md docs/design-system.md foundations.md scripts/verify-workflow.sh
git commit -m "chore(ds): require compliance across product workflow"
```

### Task 9: Final review, canonical preview, and QA handoff

**Files:**
- Modify only if verification exposes a scoped defect.
- Update: `docs/workflow.md` and the plan status after gates advance.

**Interfaces:**
- Consumes: completed Tasks 1–8.
- Produces: verified implementation revision, canonical preview revision, review evidence, and device-QA request.

- [ ] **Step 1: Run complete local verification**

Run:

```bash
npm run verify:workflow
node --test scripts/design-system/__tests__/verify.test.mjs
npm run verify:design-system
cd mobile && npx tsc --noEmit
```

Expected: every command passes with zero compliance findings.

- [ ] **Step 2: Run Storybook review**

Start Storybook from `mobile/`, review foundation roles, component variants, long content, and accessibility-size content. Record any missing native-only coverage as device-QA items, not Storybook passes.

- [ ] **Step 3: Invoke formal review skills**

Invoke `superpowers:requesting-code-review`, resolve all blocking findings, then invoke `superpowers:verification-before-completion` and rerun the complete matrix.

- [ ] **Step 4: Commit the verified revision**

Ensure the feature worktree is clean after a final coherent commit. Record the exact feature SHA.

- [ ] **Step 5: Integrate into canonical preview**

Only after all automated checks pass, safely integrate the exact feature SHA into `preview/taisa`, push `origin/preview/taisa`, and confirm the running Expo process has the preview worktree as its working directory and serves that exact clean revision.

- [ ] **Step 6: Request Baah device QA**

Ask Baah to verify readable hierarchy, 16px default body copy, semantic colors, loading/error/disabled states, accessibility text scaling, navigation, chat, recording, onboarding, and absence of clipped critical actions.

- [ ] **Step 7: Stop at the Ship gate**

Do not merge. After device QA passes, present review and verification evidence and wait for explicit Ship approval. Ship approval then authorizes the repository's verified PR merge and safe cleanup transaction.
