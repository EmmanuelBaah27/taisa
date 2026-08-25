# Design System Foundation and Enforcement

**Track:** Product
**Tier:** Full
**Status:** Build — implementation plan approved by Baah on 2026-08-25

## What is it?

Establish Taisa's design system as the mandatory foundation for every Product feature. The work preserves the current visual direction while correcting the color and typography foundations, providing the essential components screens need, migrating the current product experience, and enforcing compliance through the repository workflow and continuous integration.

The design system will continue to evolve with the product. Each future feature will reuse existing components where they fit and add only the reusable components or backwards-compatible variants that the approved feature genuinely needs.

## Why now?

Taisa has documented semantic tokens and typography utilities, but current screens frequently bypass them with raw React Native primitives, legacy Tailwind sizes, arbitrary values, and visual components outside the design-system boundary. This makes text render smaller than intended, allows visual inconsistency to accumulate, and leaves compliance dependent on reviewer discipline.

Future Product work will amplify that drift unless the foundations, component boundary, migration path, and automated workflow gate are established first.

## Acceptance criteria

### Foundations

- [ ] Taisa has one authoritative semantic color definition for product UI, with documented roles for surfaces, text, borders, actions, status, overlays, and disabled states.
- [ ] Product UI renders without raw hex, RGB, HSL, OKLCH, arbitrary Tailwind colors, or direct palette values when a semantic role applies.
- [ ] Taisa has one authoritative semantic typography scale that binds font family, size, weight, line height, and letter spacing into named roles.
- [ ] Default body copy renders at no less than 16px; 14px is reserved for secondary labels and supporting UI; 12px is reserved for genuinely tertiary metadata.
- [ ] Headings, body copy, labels, actions, helper text, and metadata render through semantic typography roles rather than independently selected size and weight utilities.
- [ ] The implemented token values, rendered Storybook examples, and `docs/design-system.md` agree; contradictory values fail verification.

### Components and adoption

- [ ] Screens can compose the current Taisa experience without selecting raw visual primitives for recurring typography, action, field, surface, feedback, or list-row patterns.
- [ ] A typed semantic text component is the standard text boundary for Product UI and exposes only approved typography and color roles.
- [ ] Foundational design-system components define their supported variants, states, accessibility behavior, tokens, exports, documentation, and Storybook coverage.
- [ ] Storybook renders the exact production component exports and production token values; no story-owned visual replica or separately maintained Storybook token value is accepted.
- [ ] Existing reusable visual components outside `mobile/src/components/ui/` are either migrated into the design system or explicitly classified as screen-specific composition.
- [ ] Current product screens are migrated to the approved semantic color, typography, and component boundaries without changing their business behavior.
- [ ] The canonical preview demonstrates the corrected type hierarchy and readable default body size across the current experience.

### Automated compliance

- [ ] `npm run verify:design-system` provides deterministic pass/fail output for design-system compliance.
- [ ] The verifier rejects unapproved raw colors, arbitrary typography values, legacy size-and-weight combinations, new `StyleSheet.create()` usage, prohibited screen-level visual primitives, undocumented design-system exports, and missing required Storybook coverage.
- [ ] Any temporary exception is explicit, narrowly scoped, documented with a reason and owner, and has an expiry; untracked suppressions fail verification.
- [ ] Design-system verification runs during Product Build, blocks Review and pull requests, blocks integration into `preview/taisa`, and is rerun during final Ship verification.
- [ ] Continuous integration runs the same repository command and exposes it as a required pull-request status check.
- [ ] `docs/workflow.md`, the Taisa workflow orchestrator, and repository agent instructions prohibit declaring Product UI complete when design-system verification has not passed.
- [ ] The migration does not preserve an indefinitely growing baseline of legacy violations; all retained exceptions are finite and visible.

### Ongoing evolution

- [ ] Every future Product plan lists the existing design-system components it will reuse and any new components or variants it requires.
- [ ] New reusable presentation patterns are implemented and verified in the design-system layer before the feature screen that consumes them.
- [ ] New components, their documentation, Storybook coverage, exports, compliance rules, and consuming feature ship together.
- [ ] Backwards-compatible variants may evolve with feature needs, while system-wide behavior changes and breaking visual changes remain subject to Baah's approval rules.
- [ ] Screen-specific business logic, navigation, data access, and one-off layout composition remain outside design-system components.

## Platform dependencies

- [ ] The current experience consolidation identifies the canonical Product runtime and preserves the design-system work that forms the migration baseline.
- [ ] The repository's pull-request checks can run the deterministic design-system verification command.
- [ ] The canonical preview publication flow can require a passing design-system verification result before integration.

## Out of scope

- Building speculative components that no approved Product feature needs.
- Redesigning Taisa's visual identity, brand palette, or interaction model.
- Dark mode or user-selectable themes.
- Changing Product behavior, navigation, data flows, coaching behavior, or backend contracts during visual migration.
- Replacing NativeWind or leaving the Expo managed workflow.
- Publishing a public design-system package or external documentation site.
- Treating Storybook snapshots alone as a substitute for device QA.
