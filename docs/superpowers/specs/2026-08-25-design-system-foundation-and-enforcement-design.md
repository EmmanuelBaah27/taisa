# Design System Foundation and Enforcement Design

**Status:** Approved
**Scope:** `docs/features/design-system-foundation-and-enforcement.md`
**Design source:** Directional chat decisions approved by Baah on 2026-08-25

The design preserves Taisa's current light visual direction. Exact values and component presentation remain subject to canonical device QA, but the semantic roles, ownership boundaries, migration rules, and enforcement gates in this document are architectural requirements.

## Design intent

Taisa should feel readable, calm, and coherent without each screen making independent visual decisions. The design system supplies a small set of semantic choices; feature screens supply content, data, navigation, state, and one-off layout composition.

The system is not a speculative library project. It establishes the foundations and components required by the current experience, then evolves inside every future Product feature as real reusable needs appear.

## Architecture

### One authoritative foundation

Colors and typography originate from one typed token module. NativeWind configuration, semantic components, documentation verification, Storybook examples, and the compliance checker consume or validate against that same definition.

The token model has two layers:

1. Primitive values exist only inside the token source and support semantic mapping.
2. Product code consumes semantic roles such as background, foreground, muted text, primary action, danger, body, label, and metadata.

Product components do not consume raw color values, palette names, arbitrary typography values, or independently chosen font-size and font-weight combinations.

### Semantic typography

Typography roles bind font family, size, weight, line height, and letter spacing as one decision. The initial mobile scale is:

| Role | Size | Intended use |
|---|---:|---|
| `display` | 28px or larger | Rare hero or onboarding statements |
| `heading` | 24px | Page titles |
| `subheading` | 20px | Section and card headings |
| `body` | 16px | Default readable product copy |
| `bodyStrong` | 16px | Emphasized product copy and prominent actions |
| `label` | 14px | Secondary labels and compact controls |
| `labelStrong` | 14px | Emphasized secondary UI |
| `metadata` | 12px | Timestamps and genuinely tertiary information only |
| `metadataStrong` | 12px | Emphasized tertiary information only |

`body` is the default. A smaller role must be intentional and semantically named. Feature code cannot request a numerical font size or add an independent weight utility.

### Semantic colors

The initial role families cover:

- app and elevated surfaces;
- primary, secondary, tertiary, inverted, and disabled text;
- default, subtle, strong, focus, and status borders;
- primary, secondary, destructive, and disabled actions;
- success, warning, danger, and information foreground/surface pairs;
- overlays, separators, and interaction feedback.

The existing light palette remains the visual starting point. The design pass reconciles duplicate names and assigns every retained value one clear semantic purpose before screen migration.

## Component boundary

Screens may use React Native primitives for non-visual behavior or genuinely one-off layout composition, but recurring visual decisions must pass through the design system. Text rendering always passes through the semantic text component.

### Component inventory

| Element | Verdict | File / name |
|---|---|---|
| Semantic text roles | New | `mobile/src/components/ui/Text.tsx` |
| Button actions | Modify | `mobile/src/components/ui/Button.tsx` — consume semantic text/color roles and complete states |
| Liquid-glass actions | Modify | existing liquid-glass surfaces — align their labels, colors, focus, disabled, and loading behavior with Button semantics |
| Form input | Modify | `mobile/src/components/ui/Input.tsx` — semantic label, helper, error, disabled, and focus behavior |
| Card/surface | Modify | `mobile/src/components/ui/Card.tsx` — semantic surfaces, borders, spacing, and typography slots |
| Badge/status label | Modify | `mobile/src/components/ui/Badge.tsx` — semantic status roles and typography |
| Icon | Modify | `mobile/src/components/ui/Icon.tsx` — semantic color API rather than raw product color literals |
| Page structure | New | `mobile/src/components/layout/Screen.tsx`, `Stack.tsx`, `Row.tsx`, `Section.tsx`, and `Divider.tsx` only where confirmed by current repeated usage |
| Page and section headings | New | semantic compositions using Text; names finalized from current screen inventory |
| Loading, empty, and error feedback | New where repeated | presentational states built from Text, Icon, Button, and layout primitives |
| Search, list rows, settings rows | Reuse/modify/extract | classify current implementations; extract only patterns with two confirmed uses |
| Navigation, chat, and recording surfaces | Reuse/modify | retain domain-specific presentation in `ui/`; migrate internal tokens and typography without changing behavior |
| Legacy top-level visual components | Classify | move reusable presentation to `ui/` or `features/`; leave only screen-specific composition outside the DS boundary |

Every foundational component defines typed props, supported variants and states, accessibility behavior, token usage, barrel export, documentation, and Storybook coverage. Business logic, data fetching, stores, navigation decisions, and feature state do not enter these components.

## Component evolution with features

Every Product plan contains a design-system inventory:

- existing components to reuse;
- existing components needing a backwards-compatible variant;
- new components justified by two confirmed uses or an approved reusable foundation need;
- screen-specific composition that deliberately remains outside the design system.

The design-system layer is implemented first and ships in the same pull request as its consuming feature. A feature cannot land a placeholder visual pattern with an untracked promise to extract it later.

Backwards-compatible variants may be added autonomously and documented. A change that alters every existing use is surfaced to Baah with its visual impact. Removed variants, renamed exports, or other breaking changes always require approval and an explicit migration.

## Compliance verifier

`npm run verify:design-system` is the single deterministic repository entry point. It reports actionable file-and-line failures and exits nonzero for violations.

The verifier checks:

- raw hex, RGB, HSL, or OKLCH values in Product UI outside approved token/configuration and exceptional rendering files;
- direct palette and arbitrary Tailwind color utilities where semantic roles are required;
- `text-xs`, `text-sm`, arbitrary text sizes, independent font-weight utilities, and other bypasses of semantic typography;
- raw React Native `Text` use in Product UI;
- new `StyleSheet.create()` usage;
- prohibited recurring visual primitives or legacy visual-component imports in screens;
- missing design-system barrel exports;
- missing component documentation;
- missing Storybook coverage for components whose contract is visually reviewable there;
- disagreement between the token registry, generated/verified documentation, and implementation;
- invalid, expired, or undocumented exceptions.

The verifier understands approved technical exceptions. Low-level animation, Skia, gradient, shadow, or platform APIs may require numerical styles or color strings that NativeWind cannot express. Those exceptions must be registered by exact file and rule with a reason, owner, and expiry or review date. Inline disable comments and broad directory exemptions are not valid substitutes.

## Workflow enforcement

Design-system verification is a required Product gate:

| Stage | Enforcement |
|---|---|
| Scope | Product acceptance criteria identify user-visible DS implications when relevant. |
| Design | Handoff maps every visual element to reuse, modify, new, or screen-specific composition and identifies token gaps. |
| Plan | Plan lists DS components and tokens, schedules the DS layer first, and includes verifier tests. |
| Build | Changed-file compliance runs throughout implementation; full verification runs before Build is declared complete. |
| Review | A full passing result is required evidence and blocks the pull request when absent or failing. |
| Preview | The verified implementation commit cannot enter `preview/taisa` until the same command passes. |
| Ship | Final verification reruns the command before merge. |

Continuous integration runs the same command on every pull request. Repository workflow instructions and agent entry points state that Product UI cannot be called complete, preview-ready, or shippable without fresh passing output.

GitHub branch protection should mark the CI design-system check required. Because repository code cannot prove an external branch-protection setting by itself, verification reports that configuration separately and the Ship checklist confirms it.

## Migration

Migration proceeds foundation-first:

1. Freeze and test the authoritative token and typography contracts.
2. Build or correct foundational components and their stories.
3. Establish the verifier with tests proving each prohibited and permitted pattern.
4. Inventory current screens and classify every violation.
5. Migrate shared components before their consuming screens.
6. Migrate screens by user journey while preserving behavior.
7. Remove migrated legacy utilities and expire temporary exceptions.
8. Verify Storybook, mobile TypeScript, the complete compliance command, canonical preview, and Baah device QA.

The initial merge does not carry an indefinitely grandfathered baseline. If a technical exception cannot be removed safely in this effort, it remains narrowly registered and time-bounded.

## States and accessibility

Foundational interactive components cover default, pressed, focused where applicable, disabled, loading, error, and selected states. Text supports React Native accessibility scaling and does not globally disable font scaling. Components maintain usable touch targets, screen-reader labels, contrast, and state announcements.

The migration must confirm that increased body sizing does not truncate critical labels or hide actions at supported accessibility text sizes. Layout adaptation is preferred over suppressing scaling.

## Token gaps

- The repository currently has conflicting typography values across `foundations.md`, `docs/design-system.md`, `global.css`, and Product usage. The new typed token registry resolves this conflict.
- Current semantic color coverage is broad but inconsistently named and bypassed. The design pass must reconcile roles before migration rather than preserve every alias.
- Component-specific animation and rendering values need an explicit technical-exception model rather than being mistaken for ordinary Product color or typography tokens.

No additional brand colors or speculative typography roles are approved by this design.

## Backend implications

None. This work changes Product presentation, repository verification, documentation, and workflow enforcement without changing APIs, stored data, coaching behavior, or backend contracts.

## Verification design

The verifier itself has fixture-based tests containing representative passing and failing files. Tests prove that each rule catches its violation, permits its defined technical exceptions, rejects expired exceptions, and produces stable actionable output.

Product verification includes:

- verifier fixture tests;
- full `npm run verify:design-system`;
- mobile TypeScript checking;
- relevant existing component tests;
- Storybook rendering of foundation roles, variants, and states;
- canonical preview publication only after automated checks pass;
- Baah device QA of typography hierarchy, readability, color roles, accessibility scaling, and migrated journeys.

## Open questions

None blocking. Exact spacing adjustments and the final visual tuning of retained light-theme values are implementation-latitude decisions reviewed through Storybook and canonical device QA.

## Ready for plan

The foundation, component boundary, evolution model, migration path, exception policy, and mandatory workflow enforcement are defined. After Baah approves this handoff, the next step is a detailed implementation plan; Build remains blocked until that plan is approved.
